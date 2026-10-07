import 'dart:math' as math;
import 'widget_test_fakes.dart';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _MemoryCodexPluginStore = MemoryCodexPluginStore;
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
  testWidgets('sends a composer message when Enter is pressed', (tester) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      '用 Enter 发送',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      controller.entries.map((entry) => entry.detail),
      contains('用 Enter 发送'),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens and applies Composer slash commands', (tester) async {
    final pluginStore = _MemoryCodexPluginStore()
      ..mcpServers.addAll(const [
        CodexMcpServer(
          name: 'codex_app',
          enabled: true,
          transportLabel: 'HTTP',
          authStatus: 'unsupported',
        ),
        CodexMcpServer(
          name: 'computer-use',
          enabled: false,
          transportLabel: '本地进程',
          authStatus: 'unsupported',
        ),
      ]);
    final git = _FakeGitProjectService()
      ..reviewBaseBranches = const ['origin/main', 'release/1.0'];
    final server = _FakeCodexAppServer()
      ..mcpServerStatusResponse = [
        {
          'name': 'codex_app',
          'authStatus': 'unsupported',
          'runtimeStatus': 'connected',
          'tools': <String, Object?>{},
        },
        {
          'name': 'computer-use',
          'authStatus': 'unsupported',
          'runtimeStatus': 'disabled',
          'tools': <String, Object?>{},
        },
      ];
    final controller =
        CodexController(
            server: server,
            pluginStore: pluginStore,
            gitProjectService: git,
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready
          ..skills = [
            CodexSkill(
              name: 'browser',
              path: '/skills/browser',
              description: '控制内置浏览器以完成本地开发任务。\n' * 80,
              enabled: true,
              scope: 'user',
              displayName: 'Browser',
              shortDescription: '控制内置浏览器',
            ),
            CodexSkill(
              name: 'openai-docs',
              path: '/skills/openai-docs',
              description: '查询 OpenAI 与 Codex 文档',
              enabled: true,
              scope: 'system',
              displayName: 'OpenAI Docs',
              shortDescription: '查询 Codex 文档',
            ),
            CodexSkill(
              name: 'long-plugin',
              path: '/skills/long-plugin',
              description: '用于验证长插件名称不会破坏菜单布局',
              enabled: true,
              scope: 'system',
              displayName:
                  'Plugin with an intentionally very long display name that must truncate',
              shortDescription: '验证动态插件名称的宽度约束',
            ),
          ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/');
    await tester.pump();

    expect(find.byKey(const Key('composer-slash-menu')), findsOneWidget);
    expect(
      find.byKey(const Key('composer-slash-command-list')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('composer-slash-skill-list')), findsNothing);
    expect(
      find.byKey(const ValueKey('composer-slash-command-codeReview')),
      findsOneWidget,
    );
    for (final kind in [
      'sideChat',
      'forkChat',
      'compact',
      'feedback',
      'archive',
      'reasoning',
      'newChat',
      'model',
    ]) {
      expect(
        find.byKey(ValueKey('composer-slash-command-$kind')),
        findsOneWidget,
      );
    }
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('composer-slash-command-archive')),
          )
          .onTap,
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const Key('composer-workspace-chip')), findsNothing);
    await tester.enterText(field, '@bro');
    await tester.pump();
    expect(find.byKey(const Key('composer-mention-menu')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-slash-skill-browser')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composer-slash-command-codeReview')),
      findsNothing,
    );
    await tester.enterText(field, '@');
    await tester.pump();
    final browserSkill = find.byKey(
      const ValueKey('composer-slash-skill-browser'),
    );
    for (var index = 0; index < 4; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 140));
    }
    expect(browserSkill, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('composer-mention-menu')),
        matching: find.text('插件'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-skill-chip-browser')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('composer-skill-chip-browser')));
    await tester.pump();
    expect(
      find.byKey(const Key('composer-skill-details-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('控制内置浏览器以完成本地开发任务'), findsOneWidget);
    expect(find.text('个人技能'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('composer-skill-details-close')));
    await tester.pump();
    expect(
      find.byKey(const Key('composer-skill-details-dialog')),
      findsNothing,
    );

    await tester.enterText(field, '@目标');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-slash-command-goal')));
    await tester.pump();
    expect(find.byKey(const Key('composer-goal-mode-control')), findsOneWidget);
    expect(
      tester.widget<TextField>(field).decoration!.hintText,
      '描述你的目标，定义可衡量的成果，以获得最佳效果',
    );
    await tester.tap(find.byKey(const Key('composer-goal-mode-control')));
    await tester.pump();
    expect(tester.widget<TextField>(field).decoration!.hintText, '随心输入');

    await tester.enterText(field, '/IDE');
    await tester.pump();

    final ideContextItem = tester.widget<InkWell>(
      find.byKey(const ValueKey('composer-slash-command-workspaceContext')),
    );
    expect(ideContextItem.onTap, isNull);
    expect(find.text('未连接 IDE 宿主，当前不可用'), findsOneWidget);

    await tester.enterText(field, '/');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('composer-slash-menu')), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, '/');

    await tester.enterText(field, '/m');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '/');
    expect(find.byKey(const Key('composer-mcp-status-panel')), findsOneWidget);
    expect(find.text('codex_app'), findsOneWidget);
    expect(find.text('computer-use'), findsOneWidget);
    expect(find.text('不支持身份验证'), findsNWidgets(2));
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('已禁用'), findsOneWidget);
    final entryCountBeforeMcpEnter = controller.entries.length;
    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.entries, hasLength(entryCountBeforeMcpEnter));
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.byKey(const Key('composer-mcp-status-panel')), findsNothing);

    await tester.enterText(field, '/代码');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-slash-command-codeReview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composer-slash-command-mcpStatus')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('composer-slash-command-codeReview')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-code-review-options-panel')),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(field).controller!.text, '/');
    expect(
      find.byKey(const Key('composer-code-review-uncommitted')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composer-code-review-base-origin/main')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('composer-code-review-base-origin/main')),
    );
    await tester.pump();
    expect(server.startedReviewThreadId, 'new-thread');
    expect(server.startedReviewTarget, {
      'type': 'baseBranch',
      'branch': 'origin/main',
    });
    expect(
      find.byKey(const Key('composer-code-review-options-panel')),
      findsNothing,
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'id': 'review-turn', 'status': 'completed'},
        },
      ),
    );
    await tester.pump();
    await tester.enterText(field, '/代码');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('composer-slash-command-codeReview')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-code-review-uncommitted')));
    await tester.pump();
    expect(server.startedReviewThreadId, 'new-thread');
    expect(server.startedReviewTarget, {'type': 'uncommittedChanges'});
    expect(find.byKey(const Key('code-review-panel')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps unavailable mention actions visible and skips them', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running-thread'
      ..activeTurnId = 'running-turn';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '@');
    await tester.pump();

    final plan = find.byKey(const ValueKey('composer-slash-command-planMode'));
    expect(plan, findsOneWidget);
    expect(tester.widget<InkWell>(plan).onTap, isNull);
    expect(find.text('任务运行时不可用'), findsOneWidget);

    for (var index = 0; index < 3; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.byKey(const Key('composer-plan-mode-chip')), findsNothing);
    expect(find.byKey(const Key('composer-record-skill-chip')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the slash menu closed while the runtime is offline', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.stopped;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/');
    await tester.pump();

    expect(find.byKey(const Key('composer-slash-menu')), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps slash review visible but disabled while running', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running-thread'
      ..activeTurnId = 'running-turn';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/');
    await tester.pump();

    final review = find.byKey(
      const ValueKey('composer-slash-command-codeReview'),
    );
    expect(review, findsOneWidget);
    expect(tester.widget<InkWell>(review).onTap, isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not execute project context without a selected project', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer());
    final composer = TextEditingController();
    addTearDown(() {
      composer.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposerPanel(
            controller: controller,
            composer: composer,
            onSend: (_) async => true,
            onQueueSteer: (_) async => true,
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('composer-field'));
    composer.text = '@当前';
    await tester.pump();

    final projectContext = find.byKey(
      const ValueKey('composer-slash-command-workspaceContext'),
    );
    expect(projectContext, findsOneWidget);
    expect(tester.widget<InkWell>(projectContext).onTap, isNull);
    expect(find.text('请先选择项目'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '@当前');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'focuses the first enabled slash command and follows mouse hover',
    (tester) async {
      final server = _FakeCodexAppServer();
      final controller =
          CodexController(
              server: server,
              pluginStore: _MemoryCodexPluginStore(),
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final field = find.byKey(const Key('composer-field'));
      await tester.enterText(field, '/');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(
        find.byKey(const Key('composer-mcp-status-panel')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.enterText(field, '/');
      await tester.pump();
      final feedback = find.byKey(
        const ValueKey('composer-slash-command-feedback'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(feedback));
      await mouse.moveTo(tester.getCenter(feedback));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('composer-feedback-dialog')), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('closes the slash menu with Tab without submitting the token', (
    tester,
  ) async {
    final controller =
        CodexController(
            server: _FakeCodexAppServer(),
            pluginStore: _MemoryCodexPluginStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/');
    await tester.pump();
    expect(find.byKey(const Key('composer-slash-menu')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(find.byKey(const Key('composer-slash-menu')), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, '/');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('submits Composer feedback through the App Server dialog', (
    tester,
  ) async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/反馈');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('composer-slash-command-feedback')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composer-feedback-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('composer-feedback-reason')),
      '菜单意外关闭',
    );
    await tester.tap(find.byKey(const Key('composer-feedback-include-logs')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-feedback-submit')));
    await tester.pumpAndSettle();

    expect(server.feedbackClassification, 'bug');
    expect(server.feedbackIncludeLogs, isTrue);
    expect(server.feedbackReason, '菜单意外关闭');
    expect(find.text('反馈已发送。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('confirms and starts Composer context compaction', (
    tester,
  ) async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'thread-1',
          'turn': {'id': 'turn-1', 'status': 'completed'},
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/压缩');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('composer-slash-command-compact')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('composer-compact-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-compact-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(server.compactedThreadId, 'thread-1');
    expect(controller.status, RuntimeStatus.running);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('forks a chat through the Composer slash command', (
    tester,
  ) async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'source-thread'
      ..activeTurnId = 'turn-1';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'source-thread',
          'turn': {'id': 'turn-1', 'status': 'completed'},
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/创建聊天分支');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('composer-slash-command-forkChat')),
    );
    await tester.pumpAndSettle();

    expect(server.forkedSourceThreadId, 'source-thread');
    expect(controller.activeThreadId, 'forked-thread');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens an independent side chat panel from Composer', (
    tester,
  ) async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'source-thread'
      ..activeTurnId = 'turn-1';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'source-thread',
          'turn': {'id': 'turn-1', 'status': 'completed'},
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(find.byKey(const Key('composer-field')), '/侧边');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('composer-slash-command-sideChat')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(server.forkedEphemeral, isTrue);
    expect(find.byKey(const Key('side-chat-panel-header')), findsOneWidget);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('side-chat-field')), '检查侧边任务');
    await tester.tap(find.byKey(const Key('side-chat-send')));
    await tester.pump();
    expect(server.startedTurnThreadId, 'forked-thread');
    expect(server.startedTurnPrompt, '检查侧边任务');

    await tester.tap(find.byKey(const Key('side-chat-close')));
    await tester.pump();
    expect(find.byKey(const Key('side-chat-panel-header')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps an uncommitted review request until an active turn accepts directions',
    (tester) async {
      final controller = CodexController(server: _FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final field = find.byKey(const Key('composer-field'));
      await tester.enterText(field, '/代码');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('composer-slash-command-codeReview')),
      );
      await tester.pumpAndSettle();

      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'initializing-turn'
        ..activeTurnId = null
        ..notifyListeners();
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('composer-code-review-uncommitted')),
      );
      await tester.pump();

      expect(find.text('等待当前任务接收审查…'), findsNothing);
      expect(
        find.byKey(const Key('composer-code-review-options-panel')),
        findsOneWidget,
      );
      expect(controller.pendingTurnSteers, isEmpty);

      controller
        ..activeTurnId = 'turn-ready'
        ..notifyListeners();
      await tester.pump();
      await tester.pump();

      expect(controller.pendingTurnSteers, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'lets timeline content pass behind the floating composer and fade',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1'
        ..threads = [_thread(id: 'thread-1')]
        ..replaceTimelineEntriesForTesting(
          List<TimelineEntry>.generate(
            18,
            (index) => TimelineEntry(
              kind: TimelineKind.agent,
              title: 'Codex',
              detail: '滚动内容 $index\n${'用于检查输入框后方滚动的文字 ' * 3}',
              createdAt: DateTime(2026, 1, 1, 0, 0, index),
            ),
          ),
        );

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump();
      await tester.pump();

      final viewport = find.byKey(const Key('conversation-viewport-stack'));
      final composer = find.byKey(const Key('composer-panel'));
      final fade = find.byKey(const Key('composer-bottom-fade'));
      final timelineFinder = find.descendant(
        of: find.byKey(
          const ValueKey('conversation-timeline-/workspace:thread-1'),
        ),
        matching: find.byType(ListView),
      );
      final timeline = tester.widget<ListView>(timelineFinder);
      final viewportBottom = tester.getBottomLeft(viewport).dy;
      var composerTop = tester.getTopLeft(composer).dy;
      final initialBottomPadding = (timeline.padding as EdgeInsets).bottom;

      expect(tester.getBottomLeft(timelineFinder).dy, viewportBottom);
      expect(composerTop, lessThan(viewportBottom));
      expect(fade, findsOneWidget);
      final fadeMask = tester.widget<ShaderMask>(fade);
      expect(fadeMask.blendMode, BlendMode.dstIn);
      expect(
        find.descendant(of: fade, matching: timelineFinder),
        findsOneWidget,
      );

      timeline.controller!.jumpTo(
        timeline.controller!.position.maxScrollExtent,
      );
      await tester.pump();
      for (final label in ['第一条调整方向', '第二条调整方向', '第三条调整方向']) {
        controller.queueTurnSteer(
          PendingTurnSteer(displayText: label, prompt: label),
        );
      }
      await tester.pump();
      await tester.pump();
      composerTop = tester.getTopLeft(composer).dy;
      expect(
        (tester.widget<ListView>(timelineFinder).padding as EdgeInsets).bottom,
        greaterThan(initialBottomPadding),
      );
      expect(timeline.controller!.position.extentAfter, lessThan(1));
      final maxOffset = timeline.controller!.position.maxScrollExtent;
      timeline.controller!.jumpTo(math.max(0, maxOffset - 120));
      await tester.pump();

      final lastMessage = find.textContaining('滚动内容 17');
      expect(lastMessage, findsOneWidget);
      expect(tester.getBottomLeft(lastMessage).dy, greaterThan(composerTop));

      for (final pending in controller.pendingTurnSteers.toList()) {
        controller.discardPendingTurnSteer(pending);
      }
      await tester.pump();
      await tester.pump();
      composerTop = tester.getTopLeft(composer).dy;
      final settledBottomPadding =
          (tester.widget<ListView>(timelineFinder).padding as EdgeInsets)
              .bottom;
      expect(
        (viewportBottom - composerTop) - settledBottomPadding,
        closeTo(-52, 0.5),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'file-change-1',
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
      timeline.controller!.jumpTo(
        timeline.controller!.position.maxScrollExtent,
      );
      await tester.pump();
      expect(
        tester.getBottomLeft(find.byKey(const Key('live-thinking-row'))).dy,
        lessThan(
          tester
                  .getTopLeft(
                    find.byKey(const Key('composer-file-change-pill')),
                  )
                  .dy -
              8,
        ),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('floats file change stats without moving the composer', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final composerField = find.byKey(const Key('composer-field'));
    final composerFieldTopBefore = tester.getTopLeft(composerField).dy;

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

    final pill = find.byKey(const Key('composer-file-change-pill'));
    final overlay = find.byKey(const Key('composer-file-change-overlay'));
    expect(pill, findsOneWidget);
    expect(overlay, findsOneWidget);
    expect(
      find.ancestor(
        of: pill,
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(composerField).dy,
      moreOrLessEquals(composerFieldTopBefore),
    );
    expect(
      tester.getTopLeft(pill).dy,
      lessThan(tester.getTopLeft(composerField).dy),
    );
    expect(
      find.descendant(of: pill, matching: find.text('1 个文件已更改')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pill, matching: find.text('+1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pill, matching: find.text('-1')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  test(
    'keeps locally cached completed commands missing from server history',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'thread-1', 'status': 'idle'},
        ]
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'turn-1',
                'items': [
                  {
                    'type': 'commandExecution',
                    'id': 'server-command',
                    'command': 'git status',
                    'aggregatedOutput': 'clean',
                  },
                  {
                    'type': 'commandExecution',
                    'id': 'shared-command',
                    'command': 'dart analyze',
                    'aggregatedOutput': 'No issues',
                  },
                ],
              },
            ],
          },
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..activeThreadId = 'thread-1';
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.command,
          title: '执行命令',
          detail: 'git status\nlocal cached output',
          createdAt: DateTime(2026),
          sourceItemId: 'local-command',
        ),
        TimelineEntry(
          kind: TimelineKind.command,
          title: '执行命令',
          detail: 'stale dart analyze',
          createdAt: DateTime(2026),
          sourceItemId: 'shared-command',
        ),
        TimelineEntry(
          kind: TimelineKind.command,
          title: '执行命令',
          detail: 'legacy command',
          createdAt: DateTime(2026),
        ),
      ]);

      await controller.resumeThread(_thread(id: 'thread-1'));

      final commands = controller.entries
          .where((entry) => entry.kind == TimelineKind.command)
          .toList();
      expect(commands.map((entry) => entry.sourceItemId), [
        'server-command',
        'shared-command',
        'local-command',
        null,
      ]);
      expect(
        commands.map((entry) => entry.detail),
        contains('git status\nlocal cached output'),
      );
      expect(commands.map((entry) => entry.detail), contains('legacy command'));
      expect(
        commands.map((entry) => entry.detail),
        isNot(contains('stale dart analyze')),
      );
      controller.dispose();
    },
  );

  test('does not merge commands from the previously open thread', () async {
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'thread-b', 'status': 'idle'},
      ]
      ..resumeResult = {
        'thread': {
          'turns': [
            {
              'id': 'turn-b',
              'items': [
                {'type': 'agentMessage', 'text': '线程 B 的回复'},
              ],
            },
          ],
        },
      };
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'thread-a';
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'thread-a command',
        createdAt: DateTime(2026),
        sourceItemId: 'thread-a-command',
      ),
    ]);

    await controller.resumeThread(_thread(id: 'thread-b'));

    expect(
      controller.entries.map((entry) => entry.detail),
      contains('线程 B 的回复'),
    );
    expect(
      controller.entries.map((entry) => entry.detail),
      isNot(contains('thread-a command')),
    );
    controller.dispose();
  });

  testWidgets('rebuilds when an explicitly injected controller changes', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    controller.createThread();
    await tester.pump();

    expect(find.text('你想让我们在 ChatGPT 中构建什么？'), findsOneWidget);
    expect(find.text('探索并理解代码'), findsOneWidget);
    expect(find.text('构建新功能、应用或工具'), findsOneWidget);
    expect(find.text('审查代码并提出修改建议'), findsOneWidget);
    expect(find.text('修复问题和失败'), findsOneWidget);

    await tester.tap(find.text('探索并理解代码'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller
          ?.text,
      '探索',
    );
    expect(find.text('探索并了解功能的工作原理'), findsOneWidget);
    expect(find.text('探索某项功能的实现方案'), findsOneWidget);
    expect(find.text('探索并比较架构方案'), findsOneWidget);
    expect(find.text('探索并编写 API 文档'), findsOneWidget);
    expect(find.text('构建新功能、应用或工具'), findsNothing);
    final enteringMenuTop = tester
        .getTopLeft(find.byKey(const Key('new-task-explore-menu')))
        .dy;
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.getTopLeft(find.byKey(const Key('new-task-explore-menu'))).dy,
      lessThan(enteringMenuTop),
    );
    await tester.pumpAndSettle();
    final exploreMenu = tester.getRect(
      find.byKey(const Key('new-task-explore-menu')),
    );
    final composerSurface = tester.getRect(
      find.byKey(const Key('composer-surface-stack')),
    );
    expect(exploreMenu.left, closeTo(composerSurface.left, 0.1));
    expect(exploreMenu.bottom, lessThan(composerSurface.top));
    expect(composerSurface.top - exploreMenu.bottom, lessThan(20));
    await tester.tap(find.text('探索并了解功能的工作原理'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller
          ?.text,
      '探索并了解功能的工作原理。',
    );
    expect(find.text('探索并理解代码'), findsOneWidget);
    expect(find.text('探索某项功能的实现方案'), findsNothing);

    await tester.tap(find.text('探索并理解代码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('composer-field')), '探索这个模块');
    await tester.pumpAndSettle();
    expect(find.text('探索并理解代码'), findsOneWidget);
    expect(find.text('探索某项功能的实现方案'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new task welcome stays usable in a narrow window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.createThread();
    await tester.pump();

    expect(find.text('你想让我们在 ChatGPT 中构建什么？'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    await tester.ensureVisible(find.text('探索并理解代码'));
    await tester.tap(find.text('探索并理解代码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-task-explore-menu')), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byKey(const Key('new-task-explore-menu'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('composer-surface-stack'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
