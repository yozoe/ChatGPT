import 'dart:io';

import 'package:chatgpt/src/presentation/files/workspace_file_preview_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a bounded UTF-8 file inside the workspace', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'workspace-preview',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final file = File('${workspace.path}/example.dart');
    await file.writeAsString('const answer = 42;');

    final preview = await WorkspaceFilePreviewReader(
      workspacePath: workspace.path,
      maximumBytes: 1024,
    ).read(file.path);

    expect(preview.content, 'const answer = 42;');
    expect(preview.error, isNull);
  });

  test('rejects an oversized file without returning partial content', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'workspace-preview',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final file = File('${workspace.path}/large.txt');
    await file.writeAsString('0123456789abcdef');

    final preview = await WorkspaceFilePreviewReader(
      workspacePath: workspace.path,
      maximumBytes: 8,
    ).read(file.path);

    expect(preview.content, isNull);
    expect(preview.error, WorkspaceFilePreviewReader.tooLargeMessage);
  });

  test('rejects a symbolic link that resolves outside the workspace', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'workspace-preview',
    );
    final external = await Directory.systemTemp.createTemp('external-preview');
    addTearDown(() => workspace.delete(recursive: true));
    addTearDown(() => external.delete(recursive: true));
    final externalFile = File('${external.path}/secret.txt');
    await externalFile.writeAsString('outside');
    final link = Link('${workspace.path}/linked.txt');
    await link.create(externalFile.path);

    final preview = await WorkspaceFilePreviewReader(
      workspacePath: workspace.path,
      maximumBytes: 1024,
    ).read(link.path);

    expect(preview.content, isNull);
    expect(preview.error, WorkspaceFilePreviewReader.outsideWorkspaceMessage);
  });
}
