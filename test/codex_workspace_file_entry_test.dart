import 'dart:io';

import 'package:chatgpt/src/presentation/files/codex_workspace_file_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the final non-empty path segment as a directory name', () {
    final entry = CodexWorkspaceFileEntry.fromFileSystemEntity(
      Directory('/tmp/project/assets'),
    );

    expect(entry.name, 'assets');
    expect(entry.isDirectory, isTrue);
  });

  test('keeps hidden directory names', () {
    final entry = CodexWorkspaceFileEntry.fromFileSystemEntity(
      Directory('/tmp/project/.git'),
    );

    expect(entry.name, '.git');
  });

  test('keeps directories visible while filtering descendant names', () {
    const directory = CodexWorkspaceFileEntry(
      path: '/tmp/project/lib',
      name: 'lib',
      isDirectory: true,
    );
    const file = CodexWorkspaceFileEntry(
      path: '/tmp/project/README.md',
      name: 'README.md',
      isDirectory: false,
    );

    expect(directory.matchesNameQuery('workspace'), isTrue);
    expect(file.matchesNameQuery('workspace'), isFalse);
    expect(file.matchesNameQuery('readme'), isTrue);
  });
}
