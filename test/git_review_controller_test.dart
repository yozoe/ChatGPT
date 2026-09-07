import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

Future<CodexController> gitReviewController(FakeGitProjectService git) async {
  final controller = CodexController(
    server: CodexAppServer(),
    gitProjectService: git,
    runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
  );
  await controller.waitForInitialConfiguration();
  controller.workspacePath = '/workspace';
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retains Git operation failures for the interface to display', () async {
    final git = FakeGitProjectService()
      ..stageError = StateError('staging is blocked');
    final controller = await gitReviewController(git);

    final succeeded = await controller.stageGitChange(
      const GitProjectChange(code: ' M', path: 'lib/main.dart'),
    );

    expect(succeeded, isFalse);
    expect(controller.gitOperationError, 'staging is blocked');
    controller.dispose();
  });

  test('filters Git changes by state and case-insensitive path query', () {
    const status = GitProjectStatus(
      isRepository: true,
      changes: [
        GitProjectChange(code: 'M ', path: 'lib/staged.dart'),
        GitProjectChange(code: ' M', path: 'lib/Editor.dart'),
        GitProjectChange(code: '??', path: 'notes/TODO.md'),
        GitProjectChange(
          code: 'R ',
          path: 'lib/new_name.dart',
          previousPath: 'lib/Legacy.dart',
        ),
      ],
    );

    expect(
      status.filteredChanges(filter: GitChangeFilter.staged),
      hasLength(2),
    );
    expect(
      status.filteredChanges(filter: GitChangeFilter.untracked).single.path,
      'notes/TODO.md',
    );
    expect(
      status.filteredChanges(query: 'EDITOR').single.path,
      'lib/Editor.dart',
    );
    expect(
      status.filteredChanges(query: 'legacy').single.path,
      'lib/new_name.dart',
    );
  });

  test('marks oversized Git diffs as truncated previews', () async {
    final directory = await Directory.systemTemp.createTemp('codex-git-large-');
    addTearDown(() => directory.delete(recursive: true));
    expect(
      (await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    await File('${directory.path}/large.txt').writeAsString(
      List.filled(GitProjectService.maximumDiffCharacters + 1, 'x').join(),
    );
    const change = GitProjectChange(code: '??', path: 'large.txt');

    final preview = await GitProjectService().readDiffPreview(
      workspace: directory.path,
      change: change,
    );

    expect(preview.truncated, isTrue);
    expect(preview.content, endsWith(GitProjectService.truncatedDiffMarker));
  });

  test('loads only read-only Git status and selected diff', () async {
    const change = GitProjectChange(code: ' M', path: 'lib/main.dart');
    final git = FakeGitProjectService()
      ..status = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: [change],
      )
      ..diff =
          'diff --git a/lib/main.dart b/lib/main.dart\n+@@ -1 +1 @@\n-old\n+new';
    final controller = await gitReviewController(git);

    await controller.refreshGitProject();
    await controller.showGitDiff(change);

    expect(git.inspectCalls, 1);
    expect(controller.gitProjectStatus!.branch, 'main');
    expect(git.requestedChange, change);
    expect(controller.gitDiff, contains('+new'));
    controller.dispose();
  });

  test('loads every changed file diff for continuous review', () async {
    const first = GitProjectChange(code: ' M', path: 'lib/first.dart');
    const second = GitProjectChange(code: '??', path: 'lib/second.dart');
    final git = FakeGitProjectService()
      ..status = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: [first, second],
      )
      ..diff = '@@ -1 +1 @@\n-old\n+new';
    final controller = await gitReviewController(git);

    await controller.refreshGitReview();

    expect(controller.gitReviewLoading, isFalse);
    expect(controller.gitReviewDiffs.keys, {
      'lib/first.dart',
      'lib/second.dart',
    });
    expect(git.requestedChanges, containsAll([first, second]));
    expect(controller.gitReviewDiffErrors, isEmpty);
    controller.dispose();
  });

  test('limits concurrent Diff reads for a large Git review', () async {
    final gate = Completer<void>();
    final changes = [
      for (var index = 0; index < 14; index++)
        GitProjectChange(code: ' M', path: 'lib/file_$index.dart'),
    ];
    final git = FakeGitProjectService()
      ..status = GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: changes,
      )
      ..diff = '@@ -1 +1 @@\n-old\n+new'
      ..diffCompleter = gate;
    final controller = await gitReviewController(git);

    final refresh = controller.refreshGitReview();
    await Future<void>.delayed(Duration.zero);

    expect(git.activeDiffReads, 6);
    expect(git.requestedChanges, hasLength(6));
    gate.complete();
    await refresh;

    expect(git.maximumActiveDiffReads, 6);
    expect(git.requestedChanges, hasLength(changes.length));
    expect(controller.gitReviewDiffs, hasLength(changes.length));
    controller.dispose();
  });
}
