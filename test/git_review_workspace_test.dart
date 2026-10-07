import 'dart:async';
import 'dart:io';
import 'widget_test_fakes.dart';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/codex_hover_popup.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _FakeRuntimeConfigurationStore = FakeRuntimeConfigurationStore;
typedef _MemoryConversationHistoryStore = MemoryConversationHistoryStore;
typedef _FakeGitProjectService = FakeGitProjectService;
typedef _FakeCodexAppServer = FakeCodexAppServer;

/// 创建具有可预测字段的测试线程。
/// Creates a test thread with predictable fields.
CodexThread _thread({
  required String id,
  String? modelProvider,
  String? model,
  String? status,
}) => CodexThread(
  id: id,
  preview: 'preview-$id',
  createdAt: 1,
  updatedAt: 2,
  modelProvider: modelProvider,
  model: model,
  status: status,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryConversationHistoryStore historyStore;
  late _FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    historyStore = _MemoryConversationHistoryStore();
    runtimeConfigurationStore = _FakeRuntimeConfigurationStore();
    CodexController.testingConversationHistoryStore = historyStore;
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  testWidgets('opens the code review surface from the completed file summary', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
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
    await tester.pump();

    expect(find.byKey(const Key('file-change-summary-card')), findsOneWidget);
    final title = tester.widget<Text>(
      find.byKey(const Key('file-change-summary-title')),
    );
    final stats = tester.widget<Text>(
      find.byKey(const Key('file-change-summary-stats')),
    );
    expect(title.style?.fontSize, 14);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(stats.style?.fontSize, 13);
    await tester.ensureVisible(
      find.byKey(const Key('review-file-changes-button')),
    );
    await tester.tap(find.byKey(const Key('review-file-changes-button')));
    await tester.pump();

    expect(find.byKey(const Key('code-review-panel')), findsOneWidget);
    expect(find.byKey(const Key('code-review-dialog')), findsNothing);
    expect(find.text('审查'), findsNWidgets(2));
    expect(find.text('lib/main.dart'), findsWidgets);
    expect(find.text('+new'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens task changes from the matching inspector summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
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

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.text('变更'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('code-review-panel')), findsOneWidget);
    expect(find.text('最新一轮'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsWidgets);
    expect(find.text('+new'), findsOneWidget);
    expect(find.text('当前任务没有可审查的文件变更。'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps review beside the conversation and preserves state across breakpoints',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(2048, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: CodexAppServer())
        ..status = RuntimeStatus.ready;
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
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
                  'diff': '@@ -4 +4 @@\n-old\n+new',
                },
                {
                  'path': 'lib/widgets/review.dart',
                  'kind': 'added',
                  'diff': '@@ -0,0 +1 @@\n+panel',
                },
              ],
            },
          },
        ),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('review-file-changes-button')),
      );
      await tester.tap(find.byKey(const Key('review-file-changes-button')));
      await tester.pump();

      expect(find.byKey(const Key('review-resize-handle')), findsOneWidget);
      expect(find.byKey(const Key('code-review-file-tree')), findsOneWidget);
      expect(find.byKey(const Key('composer-field')), findsOneWidget);
      final initialReviewWidth = tester
          .getSize(find.byKey(const Key('code-review-panel')))
          .width;
      await tester.drag(
        find.byKey(const Key('review-resize-handle')),
        const Offset(80, 0),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('code-review-panel'))).width,
        lessThanOrEqualTo(initialReviewWidth),
      );
      await tester.enterText(
        find.byKey(const Key('code-review-file-filter')),
        'review.dart',
      );
      await tester.pump();
      final tree = find.byKey(const Key('code-review-file-tree'));
      expect(
        find.descendant(of: tree, matching: find.text('review.dart')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tree, matching: find.text('main.dart')),
        findsNothing,
      );
      expect(find.text('lib/main.dart'), findsWidgets);

      await tester.binding.setSurfaceSize(const Size(1100, 760));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('code-review-panel')), findsOneWidget);
      expect(find.byKey(const Key('side-panel-collapse')), findsOneWidget);
      await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
      await tester.pump();
      expect(
        find.byKey(const Key('review-navigation-overlay')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('code-review-file-filter')))
            .controller!
            .text,
        'review.dart',
      );

      await tester.binding.setSurfaceSize(const Size(2048, 900));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-resize-handle')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('code-review-file-filter')))
            .controller!
            .text,
        'review.dart',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('keeps the composer draft while compact review covers it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.enterText(find.byKey(const Key('composer-field')), '保留未发送草稿');
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
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('review-file-changes-button')),
    );
    await tester.tap(find.byKey(const Key('review-file-changes-button')));
    await tester.pump();

    expect(find.byKey(const Key('side-panel-collapse')), findsOneWidget);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);
    await tester.tap(find.byKey(const Key('side-panel-collapse')));
    await tester.pump();

    expect(find.byKey(const Key('code-review-panel')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .text,
      '保留未发送草稿',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('collapses an inline review with Escape after opening', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
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
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('review-file-changes-button')),
    );
    await tester.tap(find.byKey(const Key('review-file-changes-button')));
    await tester.pump();

    expect(find.byKey(const Key('review-resize-handle')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const Key('code-review-panel')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders leading and inter-hunk unchanged regions', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
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
                'diff':
                    '@@ -4 +4 @@\n-old\n+new\n@@ -10 +10 @@\n-before\n+after',
              },
            ],
          },
        },
      ),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('review-file-changes-button')),
    );
    await tester.tap(find.byKey(const Key('review-file-changes-button')));
    await tester.pump();

    expect(find.text('未修改 3 行'), findsOneWidget);
    expect(find.text('未修改 5 行'), findsOneWidget);
    expect(find.text('@@ -4 +4 @@'), findsOneWidget);
    expect(find.text('@@ -10 +10 @@'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resets line state between concatenated Git patch sections', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
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
                'diff':
                    'diff --git a/lib/main.dart b/lib/main.dart\n'
                    '--- a/lib/main.dart\n'
                    '+++ b/lib/main.dart\n'
                    '@@ -8 +8 @@\n'
                    '-cached-old\n'
                    '+cached-new\n'
                    'diff --git a/lib/main.dart b/lib/main.dart\n'
                    '--- a/lib/main.dart\n'
                    '+++ b/lib/main.dart\n'
                    '@@ -8 +8 @@\n'
                    '-working-old\n'
                    '+working-new',
              },
            ],
          },
        },
      ),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('review-file-changes-button')),
    );
    await tester.tap(find.byKey(const Key('review-file-changes-button')));
    await tester.pump();

    expect(find.text('未修改 7 行'), findsNWidgets(2));
    expect(
      find.text('diff --git a/lib/main.dart b/lib/main.dart'),
      findsNWidgets(2),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'undo beside review reverses the exact turn diff and blocks duplicate taps',
    (tester) async {
      final pendingUndo = Completer<void>();
      final git = _FakeGitProjectService()..reverseCompleter = pendingUndo;
      final controller =
          CodexController(server: CodexAppServer(), gitProjectService: git)
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;
      const taskDiff =
          'diff --git a/lib/main.dart b/lib/main.dart\n'
          '--- a/lib/main.dart\n'
          '+++ b/lib/main.dart\n'
          '@@ -1 +1 @@\n'
          '-old\n'
          '+new';

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
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
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {'diff': taskDiff},
        ),
      );
      await tester.pump();

      final undo = find.byKey(const Key('undo-file-changes-button'));
      final review = find.byKey(const Key('review-file-changes-button'));
      await tester.ensureVisible(undo);
      expect(tester.getCenter(undo).dx, lessThan(tester.getCenter(review).dx));
      expect(tester.widget<TextButton>(undo).onPressed, isNotNull);

      await tester.tap(undo);
      await tester.pump();

      expect(git.reverseCalls, 1);
      expect(git.reversedDiff, taskDiff);
      expect(git.reversedExpectedPaths, ['lib/main.dart']);
      expect(tester.widget<TextButton>(undo).onPressed, isNull);
      expect(controller.fileChangeUndoRunning, isTrue);
      expect(controller.canSend, isFalse);

      await tester.tap(undo);
      await tester.pump();
      expect(git.reverseCalls, 1);

      pendingUndo.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('file-change-summary-card')), findsNothing);
      expect(find.text('已撤销本次任务的文件改动。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'blocks task-diff undo while another task runs in the background',
    () async {
      final controller = CodexController(server: _FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      expect(await controller.sendPrompt('后台处理中'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'new-thread',
            'turn': {'id': 'background-turn'},
          },
        ),
      );
      controller.createThread();
      controller.activeThreadId = 'completed-thread';
      const taskDiff =
          'diff --git a/lib/main.dart b/lib/main.dart\n'
          '--- a/lib/main.dart\n'
          '+++ b/lib/main.dart\n'
          '@@ -1 +1 @@\n'
          '-old\n'
          '+new';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'completed-thread',
            'item': {
              'type': 'fileChange',
              'changes': [
                {'path': 'lib/main.dart', 'kind': 'modified'},
              ],
            },
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {'threadId': 'completed-thread', 'diff': taskDiff},
        ),
      );

      expect(controller.hasRunningTasks, isTrue);
      expect(controller.canUndoFileChanges, isFalse);
      expect(await controller.undoFileChanges(), isFalse);
      expect(controller.fileChangeUndoError, contains('仍有任务运行'));
      controller.dispose();
    },
  );

  test(
    'clears persisted task files when switching tasks during undo',
    () async {
      final pendingUndo = Completer<void>();
      final git = _FakeGitProjectService()..reverseCompleter = pendingUndo;
      final history = _MemoryConversationHistoryStore();
      final server = _FakeCodexAppServer();
      final controller =
          CodexController(
              server: server,
              gitProjectService: git,
              conversationHistoryStore: history,
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;
      const taskDiff =
          'diff --git a/lib/main.dart b/lib/main.dart\n'
          '--- a/lib/main.dart\n'
          '+++ b/lib/main.dart\n'
          '@@ -1 +1 @@\n'
          '-old\n'
          '+new';

      await controller.resumeThread(_thread(id: 'task-a'));
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'task-a',
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
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {'threadId': 'task-a', 'diff': taskDiff},
        ),
      );

      final undo = controller.undoFileChanges();
      await Future<void>.delayed(Duration.zero);
      await controller.resumeThread(_thread(id: 'task-b'));
      expect(controller.activeThreadId, 'task-b');

      pendingUndo.complete();
      expect(await undo, isTrue);
      await controller.saveConversationHistoryForTesting();

      final snapshot = history.snapshots['/workspace']!;
      expect(snapshot.fileChangesByThreadId, isNot(contains('task-a')));
      expect(snapshot.turnDiffByThreadId, isNot(contains('task-a')));

      await controller.resumeThread(_thread(id: 'task-a'));
      expect(controller.fileChanges, isEmpty);
      expect(controller.turnDiff, isNull);
      controller.dispose();
    },
  );

  testWidgets('keeps the file summary when undo cannot be applied safely', (
    tester,
  ) async {
    final git = _FakeGitProjectService()
      ..reverseError = StateError('patch does not apply');
    final controller =
        CodexController(server: CodexAppServer(), gitProjectService: git)
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
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
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {
          'diff':
              'diff --git a/lib/main.dart b/lib/main.dart\n'
              '--- a/lib/main.dart\n'
              '+++ b/lib/main.dart\n'
              '@@ -1 +1 @@\n-old\n+new',
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('undo-file-changes-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('file-change-summary-card')), findsOneWidget);
    expect(find.text('patch does not apply'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('previews an edited file when the pointer hovers its row', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {'path': 'lib/main.dart', 'kind': 'modified', 'diff': ''},
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': '@@ -432 +432 @@\n-old\n+new'},
      ),
    );
    await tester.pump();

    final row = find.byKey(const ValueKey('file-change-row-lib/main.dart'));
    await tester.ensureVisible(row);
    final rowMouseRegion = tester.widget<MouseRegion>(row);
    rowMouseRegion.onEnter?.call(const PointerEnterEvent());
    await tester.pump();

    expect(find.byKey(const Key('file-change-hover-preview')), findsNothing);
    await tester.pump(codexHoverPopupDelay - const Duration(milliseconds: 1));
    expect(find.byKey(const Key('file-change-hover-preview')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const Key('file-change-hover-preview')), findsOneWidget);
    expect(find.text('lib/main.dart'), findsWidgets);
    expect(find.textContaining('432  -old'), findsOneWidget);
    expect(find.textContaining('+new'), findsOneWidget);
    final previewRect = tester.getRect(
      find.byKey(const Key('file-change-hover-preview')),
    );
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(previewRect.left, greaterThanOrEqualTo(0));
    expect(previewRect.top, greaterThanOrEqualTo(0));
    expect(previewRect.right, lessThanOrEqualTo(viewport.width));
    expect(previewRect.bottom, lessThanOrEqualTo(viewport.height));

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': '@@ -432 +432 @@\n-old\n+updated'},
      ),
    );
    await tester.pump();
    expect(controller.fileChanges.single.diff, isEmpty);
    await tester.pump();
    expect(find.textContaining('+updated'), findsOneWidget);
    expect(find.textContaining('+new'), findsNothing);

    rowMouseRegion.onExit?.call(const PointerExitEvent());
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.byKey(const Key('file-change-hover-preview')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('previews an edited SVG as an image on hover', (tester) async {
    final directory = Directory.systemTemp.createTempSync('codex-svg-hover-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final svgPath = '${directory.path}/preview.svg';
    File(svgPath).writeAsStringSync(
      '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80">'
      '<circle cx="40" cy="40" r="30" fill="red"/></svg>',
    );
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {'path': svgPath, 'kind': 'modified', 'diff': ''},
            ],
          },
        },
      ),
    );
    await tester.pump();
    final row = find.byKey(ValueKey('file-change-row-$svgPath'));
    final mouseRegion = tester.widget<MouseRegion>(row);
    mouseRegion.onEnter?.call(const PointerEnterEvent());
    await tester.pump(codexHoverPopupDelay);

    expect(find.byKey(const Key('file-change-hover-preview')), findsOneWidget);
    expect(find.textContaining('SVG'), findsNothing);
    mouseRegion.onExit?.call(const PointerExitEvent());
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.byKey(const Key('file-change-hover-preview')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'hydrates a missing file Diff from the read-only Git workspace',
    () async {
      final git = _FakeGitProjectService()
        ..status = const GitProjectStatus(
          isRepository: true,
          changes: [GitProjectChange(code: '??', path: 'hello.py')],
        )
        ..diff = 'diff --git a/hello.py b/hello.py\n+Hello, world!';
      final controller =
          CodexController(server: CodexAppServer(), gitProjectService: git)
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {
              'type': 'fileChange',
              'changes': [
                {'path': '/workspace/hello.py', 'kind': 'added'},
              ],
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.fileChanges.single.diff, contains('+Hello, world!'));
      expect(git.requestedChange?.isUntracked, isTrue);
      controller.dispose();
    },
  );

  testWidgets('keeps aggregate Diff out of the reviewed file count', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {'path': 'hello.py', 'kind': 'added'},
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': '@@ -0 +1 @@\n+Hello, world!'},
      ),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('review-file-changes-button')),
    );
    await tester.tap(find.byKey(const Key('review-file-changes-button')));
    await tester.pump();

    expect(find.byKey(const Key('code-review-file-count')), findsOneWidget);
    expect(find.text('1 个文件'), findsOneWidget);
    expect(find.text('本次任务完整 Diff'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders the right inspector as a Codex environment card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspaceRoot = Directory.current.path;
    final sharedRoot = '$workspaceRoot/lib';
    final unusedRoot = '$workspaceRoot/test';
    final runtimeStore = _FakeRuntimeConfigurationStore()
      ..workspace = workspaceRoot
      ..additionalWorkspaces = [sharedRoot, unusedRoot];
    late CodexController controller;
    await tester.runAsync(() async {
      controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
      );
      await controller.waitForInitialConfiguration();
    });
    controller.status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final emptyCardFinder = find.byKey(const Key('codex-environment-card'));
    expect(
      find.descendant(of: emptyCardFinder, matching: find.text('变更')),
      findsNothing,
    );
    expect(
      find.descendant(of: emptyCardFinder, matching: find.text('暂无')),
      findsOneWidget,
    );
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'README.md',
                'kind': 'modified',
                'diff': 'diff --git a/README.md b/README.md',
              },
              {
                'path': '$sharedRoot/src/shared.dart',
                'kind': 'modified',
                'diff': '+one\n+two\n-old',
              },
            ],
          },
        },
      ),
    );
    await tester.pump();

    final card = tester.widget<Container>(
      find.byKey(const Key('codex-environment-card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    final cardFinder = find.byKey(const Key('codex-environment-card'));

    expect(find.text('环境信息'), findsOneWidget);
    expect(
      find.descendant(of: cardFinder, matching: find.text('变更')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: cardFinder,
        matching: find.text(workspaceRootName(workspaceRoot)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardFinder,
        matching: find.text(workspaceRootName(sharedRoot)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardFinder,
        matching: find.text(workspaceRootName(unusedRoot)),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('+?')),
      findsNothing,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('+2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('-1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('-?')),
      findsNothing,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('本地')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('提交或推送')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('任务文件')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('2 个')),
      findsOneWidget,
    );
    final environmentTitle = tester.widget<Text>(find.text('环境信息'));
    final changeLabels = tester.widgetList<Text>(
      find.descendant(of: cardFinder, matching: find.text('变更')),
    );
    final taskFilesLabel = tester.widget<Text>(
      find.descendant(of: cardFinder, matching: find.text('任务文件')),
    );
    expect(environmentTitle.style?.fontSize, 15);
    expect(changeLabels.every((label) => label.style?.fontSize == 13), isTrue);
    expect(taskFilesLabel.style?.fontSize, 13);
    expect(decoration.borderRadius, BorderRadius.circular(28));
    await tester.pumpWidget(const SizedBox());
  });

  test('groups task changes once under involved workspace roots', () {
    const mainChange = CodexFileChange(
      path: 'lib/main.dart',
      kind: 'modified',
      diff: '+main\n-old',
    );
    const additionalChange = CodexFileChange(
      path: '/workspace/shared_api/lib/api.dart',
      kind: 'modified',
      diff: '+one\n+two\n-old',
    );
    const nestedChange = CodexFileChange(
      path: 'packages/shared_ui/lib/button.dart',
      kind: 'modified',
      diff: '+button',
    );
    final groups = groupTaskFileChanges(
      primaryRoot: '/workspace/main_app',
      additionalRoots: const [
        '/workspace/shared_api',
        '/workspace/main_app/packages/shared_ui',
        '/workspace/unused_app',
      ],
      changes: const [mainChange, additionalChange, nestedChange],
    );

    expect(groups.map((group) => workspaceRootName(group.root)), [
      'main_app',
      'shared_api',
      'shared_ui',
    ]);
    expect(groups[0].changes, [mainChange]);
    expect(groups[1].changes, [additionalChange]);
    expect(groups[2].changes, [nestedChange]);
    expect(groups.expand((group) => group.changes), hasLength(3));
  });

  testWidgets('opens a searchable branch menu beside the inspector', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const change = GitProjectChange(code: ' M', path: 'lib/editor.dart');
    final git = _FakeGitProjectService()
      ..status = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: [change],
      )
      ..localBranches = const [
        'main',
        '6.11.0',
        'codex/token-security-squashed',
      ];
    final controller =
        CodexController(server: CodexAppServer(), gitProjectService: git)
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready
          ..gitProjectStatus = git.status;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final branchRect = tester.getRect(find.text('main'));
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();

    final menu = find.byKey(const Key('inspector-branch-menu'));
    expect(menu, findsOneWidget);
    expect(tester.getRect(menu).right, lessThan(branchRect.left));
    expect(find.text('分支'), findsOneWidget);
    expect(find.text('未提交：1 个文件'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('创建并检出新分支...'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('inspector-branch-search')),
      '6.11',
    );
    await tester.pump();
    expect(find.text('6.11.0'), findsOneWidget);
    expect(find.text('codex/token-security-squashed'), findsNothing);

    await tester.tap(find.text('6.11.0'));
    await tester.pumpAndSettle();
    expect(git.checkedOutBranch, '6.11.0');
    expect(controller.gitProjectStatus?.branch, '6.11.0');

    await tester.tap(find.text('6.11.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inspector-create-branch')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('inspector-new-branch-field')),
      'feature/inspector-menu',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(git.createdBranch, 'feature/inspector-menu');
    expect(controller.gitProjectStatus?.branch, 'feature/inspector-menu');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('discards a branch menu loaded for an inactive workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final branchLoad = Completer<void>();
    final git = _FakeGitProjectService()
      ..status = const GitProjectStatus(isRepository: true, branch: 'main')
      ..localBranches = const ['main', 'release']
      ..localBranchesCompleter = branchLoad;
    final controller =
        CodexController(server: CodexAppServer(), gitProjectService: git)
          ..workspacePath = '/workspace-one'
          ..status = RuntimeStatus.ready
          ..gitProjectStatus = git.status;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.text('main'));
    await tester.pump();
    expect(git.requestedLocalBranchesWorkspace, '/workspace-one');
    controller.workspacePath = '/workspace-two';
    branchLoad.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inspector-branch-menu')), findsNothing);
    expect(git.checkedOutBranch, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
