import 'dart:io';

import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lists review branches as strings from a Git process result', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'codex-desk-git-branches-',
    );
    addTearDown(() => workspace.delete(recursive: true));

    Future<void> git(List<String> arguments) async {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: workspace.path,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }

    await git(const ['init', '--initial-branch=review-base']);
    await git(const ['config', 'user.email', 'test@example.com']);
    await git(const ['config', 'user.name', 'Codex Desk Test']);
    await File('${workspace.path}/README.md').writeAsString('test');
    await git(const ['add', 'README.md']);
    await git(const ['commit', '-m', 'Initialize test repository']);

    final branches = await GitProjectService().listReviewBaseBranches(
      workspace.path,
    );

    expect(branches, contains('review-base'));
    expect(branches, everyElement(isA<String>()));
  });
}
