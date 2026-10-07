import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  late MemoryConversationHistoryStore historyStore;
  late FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    historyStore = MemoryConversationHistoryStore();
    runtimeConfigurationStore = FakeRuntimeConfigurationStore();
    CodexController.testingConversationHistoryStore = historyStore;
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  test(
    'keeps the task file summary across follow-up turns and failed starts',
    () async {
      final server = FakeCodexAppServer();
      final git = FakeGitProjectService();
      final controller = CodexController(server: server, gitProjectService: git)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      const firstDiff =
          'diff --git a/first.txt b/first.txt\n'
          '--- a/first.txt\n'
          '+++ b/first.txt\n'
          '@@ -1 +1 @@\n-old\n+first';
      const secondDiff =
          'diff --git a/second.txt b/second.txt\n'
          '--- a/second.txt\n'
          '+++ b/second.txt\n'
          '@@ -1 +1 @@\n-old\n+second';

      expect(await controller.sendPrompt('first turn'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {
              'type': 'fileChange',
              'changes': [
                {'path': 'first.txt', 'kind': 'modified', 'diff': firstDiff},
              ],
            },
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {'diff': firstDiff},
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );

      server.startTurnError = StateError('next turn rejected');
      expect(await controller.sendPrompt('failed turn'), isFalse);
      expect(controller.fileChanges.single.path, 'first.txt');
      expect(controller.turnDiff, firstDiff);

      server.startTurnError = null;
      expect(await controller.sendPrompt('second turn'), isTrue);
      expect(controller.fileChanges.single.path, 'first.txt');
      expect(controller.turnDiff, isNull);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {
              'type': 'fileChange',
              'changes': [
                {'path': 'second.txt', 'kind': 'modified', 'diff': secondDiff},
              ],
            },
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {'diff': secondDiff},
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );

      expect(controller.fileChanges.map((change) => change.path), [
        'first.txt',
        'second.txt',
      ]);
      expect(controller.turnFileChanges.map((change) => change.path), [
        'second.txt',
      ]);
      expect(controller.turnDiff, secondDiff);
      expect(controller.canUndoFileChanges, isTrue);
      expect(await controller.undoFileChanges(), isTrue);
      expect(git.reversedDiff, secondDiff);
      controller.dispose();
    },
  );

  test(
    'undoing a later turn restores the earlier version of the same file',
    () async {
      final server = FakeCodexAppServer();
      final git = FakeGitProjectService();
      final controller = CodexController(server: server, gitProjectService: git)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      const firstDiff =
          'diff --git a/lib/main.dart b/lib/main.dart\n'
          '--- a/lib/main.dart\n'
          '+++ b/lib/main.dart\n'
          '@@ -1 +1 @@\n-old\n+first';
      const secondDiff =
          'diff --git a/lib/main.dart b/lib/main.dart\n'
          '--- a/lib/main.dart\n'
          '+++ b/lib/main.dart\n'
          '@@ -1 +1 @@\n+first\n+second';

      expect(await controller.sendPrompt('first change'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {
              'type': 'fileChange',
              'changes': [
                {
                  'path': 'lib/main.dart',
                  'kind': 'modified',
                  'diff': firstDiff,
                },
              ],
            },
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {'diff': firstDiff},
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );

      expect(await controller.sendPrompt('second change'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {
              'type': 'fileChange',
              'changes': [
                {
                  'path': 'lib/main.dart',
                  'kind': 'modified',
                  'diff': secondDiff,
                },
              ],
            },
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {'diff': secondDiff},
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );

      expect(controller.canUndoFileChanges, isTrue);
      expect(await controller.undoFileChanges(), isTrue);
      expect(git.reversedDiff, secondDiff);
      expect(controller.fileChanges.single.diff, firstDiff);
      expect(controller.turnFileChanges, isEmpty);
      controller.dispose();
    },
  );

  test('keeps undo disabled for a truncated task Diff', () async {
    final controller =
        CodexController(
            server: CodexAppServer(),
            gitProjectService: FakeGitProjectService(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'lib/main.dart',
                'kind': 'modified',
                'diff': '@@ -1 +1 @@\n-old\n+new',
              },
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'turn/diff/updated',
        params: {
          'diff':
              'diff --git a/lib/main.dart b/lib/main.dart\n${GitProjectService.truncatedDiffMarker}',
        },
      ),
    );

    expect(controller.canUndoFileChanges, isFalse);
    expect(await controller.undoFileChanges(), isFalse);
    expect(controller.fileChangeUndoError, contains('Diff 不完整'));
    controller.dispose();
  });

  test('keeps undo disabled for a binary-only task Diff', () async {
    final controller =
        CodexController(
            server: CodexAppServer(),
            gitProjectService: FakeGitProjectService(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {'path': 'assets/logo.png', 'kind': 'modified'},
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {
          'diff':
              'diff --git a/assets/logo.png b/assets/logo.png\n'
              'index 123..456 100644\n'
              'Binary files a/assets/logo.png and b/assets/logo.png differ',
        },
      ),
    );

    expect(controller.canUndoFileChanges, isFalse);
    expect(await controller.undoFileChanges(), isFalse);
    expect(controller.fileChangeUndoError, contains('Diff 不完整'));
    controller.dispose();
  });

  test('restores task files after a follow-up with no file changes', () async {
    final workspaceDirectory = await Directory.systemTemp.createTemp(
      'codex-desk-thread-files-follow-up-',
    );
    addTearDown(() => workspaceDirectory.delete(recursive: true));
    final runtimeStore = FakeRuntimeConfigurationStore();
    final firstServer = FakeCodexAppServer();
    final firstController = CodexController(
      server: firstServer,
      runtimeConfigurationStore: runtimeStore,
      conversationHistoryStore: historyStore,
    );
    await firstController.selectWorkspace(workspaceDirectory.path);
    firstController.status = RuntimeStatus.ready;
    expect(await firstController.sendPrompt('make a file change'), isTrue);
    firstController.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'lib/main.dart',
                'kind': 'modified',
                'diff': '+thread change',
              },
            ],
          },
        },
      ),
    );
    firstController.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );

    expect(await firstController.sendPrompt('only explain the change'), isTrue);
    firstController.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );
    expect(firstController.fileChanges.single.path, 'lib/main.dart');
    expect(firstController.turnFileChanges, isEmpty);
    expect(firstController.turnDiff, isNull);
    await firstController.saveConversationHistoryForTesting();
    firstController.dispose();

    final restoredController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: runtimeStore,
      conversationHistoryStore: historyStore,
    );
    await restoredController.waitForInitialConfiguration();

    expect(restoredController.activeThreadId, 'new-thread');
    expect(restoredController.fileChanges.single.path, 'lib/main.dart');
    expect(restoredController.fileChanges.single.diff, '+thread change');
    restoredController.dispose();
  });

  testWidgets('hides legacy per-file change records from the conversation', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '文件变更',
        detail: '{type: update} lib/main.dart',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '变更已完成。',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.text('文件变更'), findsNothing);
    expect(find.text('{type: update} lib/main.dart'), findsNothing);
    expect(find.text('变更已完成。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hides legacy file change records following a command activity', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'dart format',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '文件变更',
        detail: '{type: update} lib/main.dart',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.text('已运行了命令'), findsOneWidget);
    expect(find.text('已运行 dart format'), findsNothing);
    expect(find.text('文件变更'), findsNothing);
    expect(find.text('{type: update} lib/main.dart'), findsNothing);

    await tester.tap(find.text('已运行了命令'));
    await tester.pump();

    expect(find.text('已运行 dart format'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
