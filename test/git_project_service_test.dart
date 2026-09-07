import 'dart:io';

import 'package:chatgpt/src/domain/git_project_status.dart';
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

  test('reads and reverts an untracked file even when Git hides it', () async {
    final directory = await Directory.systemTemp.createTemp('codex-git-');
    addTearDown(() => directory.delete(recursive: true));
    expect(
      (await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    await File('${directory.path}/new_file.txt').writeAsString('new content\n');
    expect(
      (await Process.run('git', [
        'config',
        'status.showUntrackedFiles',
        'no',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    final service = GitProjectService();

    final status = await service.inspect(directory.path);

    expect(status.isRepository, isTrue);
    final change = status.changes.singleWhere(
      (candidate) => candidate.path == 'new_file.txt',
    );
    expect(change.isUntracked, isTrue);
    final diff = await service.readDiff(
      workspace: directory.path,
      change: change,
    );
    expect(diff, contains('+new content'));

    await service.revertFile(workspace: directory.path, change: change);
    expect(await File('${directory.path}/new_file.txt').exists(), isFalse);
  });

  test('reverse applies an exact task diff and preserves conflicts', () async {
    final directory = await Directory.systemTemp.createTemp('codex-undo-diff-');
    addTearDown(() => directory.delete(recursive: true));
    expect(
      (await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    final file = File('${directory.path}/new_file.txt');
    await file.writeAsString('new content   \n');
    final service = GitProjectService();
    const change = GitProjectChange(code: '??', path: 'new_file.txt');
    final diff = await service.readDiff(
      workspace: directory.path,
      change: change,
    );

    await file.writeAsString('new content   \nlater edit\n');
    await expectLater(
      service.reverseApplyDiff(
        workspace: directory.path,
        diff: diff,
        expectedPaths: const ['new_file.txt'],
      ),
      throwsA(isA<StateError>()),
    );
    expect(await file.readAsString(), 'new content   \nlater edit\n');

    await file.writeAsString('new content   \n');
    await service.reverseApplyDiff(
      workspace: directory.path,
      diff: diff,
      expectedPaths: [file.path],
    );
    expect(await file.exists(), isFalse);
  });

  test('rejects a task diff whose paths do not match its summary', () async {
    final directory = await Directory.systemTemp.createTemp(
      'codex-undo-paths-',
    );
    addTearDown(() => directory.delete(recursive: true));
    expect(
      (await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    final secret = File('${directory.path}/secret.txt');
    await secret.writeAsString('secret change\n');
    final service = GitProjectService();
    final diff = await service.readDiff(
      workspace: directory.path,
      change: const GitProjectChange(code: '??', path: 'secret.txt'),
    );

    await expectLater(
      service.reverseApplyDiff(
        workspace: directory.path,
        diff: diff,
        expectedPaths: const ['README.md'],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('文件列表不一致'),
        ),
      ),
    );
    expect(await secret.readAsString(), 'secret change\n');
  });

  test('refuses to reverse a task diff touching staged files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'codex-undo-staged-',
    );
    addTearDown(() => directory.delete(recursive: true));
    expect(
      (await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    final file = File('${directory.path}/tracked.txt');
    await file.writeAsString('old\n');
    expect(
      (await Process.run('git', [
        'add',
        'tracked.txt',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    expect(
      (await Process.run('git', [
        '-c',
        'user.name=Codex Test',
        '-c',
        'user.email=codex@example.com',
        'commit',
        '-qm',
        'initial',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    await file.writeAsString('new\n');
    final service = GitProjectService();
    final diff = await service.readDiff(
      workspace: directory.path,
      change: const GitProjectChange(code: ' M', path: 'tracked.txt'),
    );
    expect(
      (await Process.run('git', [
        'add',
        'tracked.txt',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );

    await expectLater(
      service.reverseApplyDiff(
        workspace: directory.path,
        diff: diff,
        expectedPaths: const ['tracked.txt'],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('暂存改动'),
        ),
      ),
    );
    expect(await file.readAsString(), 'new\n');
    final stagedDiff = await Process.run('git', [
      'diff',
      '--cached',
      '--',
      'tracked.txt',
    ], workingDirectory: directory.path);
    expect(stagedDiff.stdout, contains('+new'));
  });
}
