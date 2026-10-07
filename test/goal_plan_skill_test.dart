import 'dart:async';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/domain/task_plan.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_submission.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets('shows goals, plan mode, and skills from the composer menu', (
    tester,
  ) async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..selectedModelId = 'gpt-test'
      ..modelOptions = const [
        CodexModelOption(
          id: 'gpt-test',
          displayName: 'GPT Test',
          description: '',
          isDefault: true,
        ),
      ]
      ..skills = const [
        CodexSkill(
          name: 'skill-creator',
          path: '/skills/skill-creator/SKILL.md',
          description: 'Create reusable skills',
          enabled: true,
          scope: 'system',
          displayName: 'Skill Creator',
        ),
        CodexSkill(
          name: 'documents',
          path: '/skills/documents/SKILL.md',
          description: 'Create and edit documents',
          enabled: true,
          scope: 'system',
          displayName: 'Documents',
        ),
        CodexSkill(
          name: 'pdf',
          path: '/skills/pdf/SKILL.md',
          description: 'Read PDFs',
          enabled: true,
          scope: 'system',
          displayName: 'PDF',
        ),
        CodexSkill(
          name: 'spreadsheets',
          path: '/skills/spreadsheets/SKILL.md',
          description: 'Edit spreadsheets',
          enabled: true,
          scope: 'system',
          displayName: 'Spreadsheets',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(find.byKey(const Key('composer-field')), '保留原有草稿');
    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    expect(find.text('文件和文件夹'), findsOneWidget);
    expect(find.text('附加 workspace'), findsOneWidget);
    expect(find.text('插件'), findsAtLeastNWidgets(1));
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Spreadsheets'), findsOneWidget);
    expect(find.text('Create and edit documents'), findsOneWidget);
    expect(find.text('Read, create, and verify PDFs'), findsOneWidget);
    expect(find.text('Create and edit spreadsheets'), findsOneWidget);
    expect(find.byKey(const Key('draw-menu-item')), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuItem<AddMenuAction>>(
            find.byKey(const Key('draw-menu-item')),
          )
          .enabled,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('draw-menu-item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sketch-canvas-dialog')), findsOneWidget);
    expect(find.byKey(const Key('sketch-attach-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sketch-cancel-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sketch-canvas-dialog')), findsNothing);

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-goal-menu-item')));
    await tester.pump();
    expect(find.byKey(const Key('composer-goal-dialog')), findsNothing);
    expect(find.byKey(const Key('composer-goal-mode-control')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .decoration!
          .hintText,
      '描述你的目标，定义可衡量的成果，以获得最佳效果',
    );
    await tester.tap(find.byKey(const Key('composer-goal-mode-control')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .text,
      '保留原有草稿',
    );

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-plan-mode-menu-item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-plan-mode-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-skill-documents')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-skill-chip-documents')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-skill-pdf')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-skill-spreadsheets')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-skill-chip-documents')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('composer-skill-chip-pdf')), findsOneWidget);
    expect(
      find.byKey(const Key('composer-skill-chip-spreadsheets')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-skill-menu-item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-record-skill-chip')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'toggles plan mode with Shift+Tab and disables it while running',
    (tester) async {
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      await tester.tap(find.byKey(const Key('composer-field')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.byKey(const Key('composer-plan-mode-chip')), findsOneWidget);

      controller.activeThreadId = 'thread-plan';
      controller.setComposerPlanMode(true);
      controller
        ..status = RuntimeStatus.running
        ..activeTurnId = 'turn-plan';
      controller.handleServerEventForTesting(
        const ServerEvent(method: 'turn/started', params: {}),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer-add-button')));
      await tester.pump(const Duration(milliseconds: 500));

      final item = tester.widget<PopupMenuItem<AddMenuAction>>(
        find.byKey(const Key('add-plan-mode-menu-item')),
      );
      expect(item.enabled, isFalse);
      expect(find.text('任务运行时不可用'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('composer-plan-mode-chip')),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('composer-plan-mode-chip')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('isolates concurrent goal operations and errors by thread', () async {
    final server = FakeCodexAppServer();
    final firstOperation = Completer<JsonMap?>();
    final secondOperation = Completer<JsonMap?>();
    server.threadGoalUpdateCompleters.addAll({
      'goal-a': firstOperation,
      'goal-b': secondOperation,
    });
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'goal-a';
    addTearDown(controller.dispose);

    void publishGoal(String threadId) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'thread/goal/updated',
          params: {
            'threadId': threadId,
            'goal': {
              'threadId': threadId,
              'objective': '完成 $threadId',
              'status': 'active',
              'tokensUsed': 0,
              'timeUsedSeconds': 0,
            },
          },
        ),
      );
    }

    publishGoal('goal-a');
    final firstResult = controller.pauseActiveGoal();
    expect(controller.goalOperationInProgress, isTrue);

    controller.activeThreadId = 'goal-b';
    publishGoal('goal-b');
    expect(controller.goalOperationInProgress, isFalse);
    final secondResult = controller.pauseActiveGoal();
    expect(controller.goalOperationInProgress, isTrue);

    controller.activeThreadId = 'goal-a';
    expect(controller.goalOperationInProgress, isTrue);
    expect(await controller.resumeActiveGoal(), isFalse);
    firstOperation.completeError(StateError('目标 A 更新失败'));
    expect(await firstResult, isFalse);
    expect(controller.goalOperationError, contains('目标 A 更新失败'));

    controller.activeThreadId = 'goal-b';
    expect(controller.goalOperationInProgress, isTrue);
    expect(controller.goalOperationError, isNull);
    secondOperation.complete(null);
    expect(await secondResult, isTrue);
    expect(controller.goalOperationInProgress, isFalse);

    controller.activeThreadId = 'goal-a';
    expect(controller.goalOperationError, contains('目标 A 更新失败'));
  });

  testWidgets('shows and manages the active thread goal above the composer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'thread-goal';

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'thread-goal',
          'goal': {
            'threadId': 'thread-goal',
            'objective': '完成目标模式复刻',
            'status': 'active',
            'tokenBudget': 1000,
            'tokensUsed': 250,
            'timeUsedSeconds': 75,
          },
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('goal-progress-row')), findsOneWidget);
    expect(find.text('完成目标模式复刻'), findsOneWidget);
    expect(find.text('250 / 1000 tokens · 累计 1 分钟'), findsOneWidget);

    await tester.tap(find.byKey(const Key('goal-pause-resume-button')));
    await tester.pumpAndSettle();
    expect(server.threadGoalStatus, 'paused');
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.byKey(const Key('goal-progress-row-running')), findsNothing);
    expect(find.byKey(const Key('goal-progress-status')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('goal-progress-row'))).height,
      greaterThan(50),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'thread-goal',
          'goal': {
            'threadId': 'thread-goal',
            'objective': '完成目标模式复刻',
            'status': 'blocked',
            'tokensUsed': 250,
            'timeUsedSeconds': 75,
          },
        },
      ),
    );
    await tester.pump();
    expect(find.text('需要输入'), findsOneWidget);
    expect(find.byKey(const Key('goal-pause-resume-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('goal-actions-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑目标'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('goal-edit-field')),
      '完成目标模式和计划模式复刻',
    );
    await tester.tap(find.byKey(const Key('goal-edit-save-button')));
    await tester.pumpAndSettle();
    expect(server.threadGoal, '完成目标模式和计划模式复刻');
    expect(find.text('完成目标模式和计划模式复刻'), findsOneWidget);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'thread-goal',
          'goal': {
            'threadId': 'thread-goal',
            'objective': '完成目标模式和计划模式复刻',
            'status': 'usageLimited',
            'tokensUsed': 1000,
            'timeUsedSeconds': 120,
          },
        },
      ),
    );
    await tester.pump();
    expect(find.text('用量已达上限'), findsOneWidget);
    expect(find.byKey(const Key('goal-pause-resume-button')), findsNothing);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'thread-goal',
          'goal': {
            'threadId': 'thread-goal',
            'objective': '完成目标模式和计划模式复刻',
            'status': 'budgetLimited',
            'tokensUsed': 1000,
            'timeUsedSeconds': 120,
          },
        },
      ),
    );
    await tester.pump();
    expect(find.text('预算已用尽'), findsOneWidget);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'thread-goal',
          'goal': {
            'threadId': 'thread-goal',
            'objective': '完成目标模式和计划模式复刻',
            'status': 'complete',
            'tokensUsed': 1000,
            'timeUsedSeconds': 120,
          },
        },
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('goal-progress-row')), findsNothing);

    // The completed goal card is gone, so clear it through the controller API.
    expect(await controller.clearActiveGoal(), isTrue);
    await tester.pumpAndSettle();
    expect(server.clearThreadGoalCalls, 1);
    expect(find.byKey(const Key('goal-progress-row')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps a waiting-for-input goal in the detailed state row', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final writes = <JsonMap>[];
    final controller =
        CodexController(server: CodexAppServer(messageSink: writes.add))
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.running
          ..activeThreadId = 'waiting-goal'
          ..activeTurnId = 'waiting-turn';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'waiting-goal',
          'goal': {
            'threadId': 'waiting-goal',
            'objective': '等待用户确认后继续',
            'status': 'active',
            'tokensUsed': 20,
            'timeUsedSeconds': 12,
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/tool/requestUserInput',
        requestId: 'waiting-input-request',
        params: {
          'threadId': 'waiting-goal',
          'turnId': 'waiting-turn',
          'itemId': 'waiting-input-item',
          'isBlocking': true,
          'questions': [
            {
              'id': 'confirm',
              'header': '确认',
              'question': '是否继续执行这个目标？',
              'options': [
                {'label': '继续', 'description': '继续执行当前目标'},
                {'label': '停止', 'description': '停止当前目标'},
              ],
            },
          ],
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('user-input-panel')), findsOneWidget);
    expect(find.text('是否继续执行这个目标？'), findsOneWidget);
    expect(find.byKey(const Key('goal-progress-row')), findsOneWidget);
    expect(find.byKey(const Key('goal-progress-row-running')), findsNothing);
    expect(find.text('等待输入'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('user-input-panel'))).height,
      lessThanOrEqualTo(440),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uses the compact official-style bar while a goal is running', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running-goal';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'running-goal',
          'goal': {
            'threadId': 'running-goal',
            'objective': '执行官方目标样式核对',
            'status': 'active',
            'tokenBudget': 1000,
            'tokensUsed': 250,
            'timeUsedSeconds': 49866,
          },
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('goal-progress-row-running')), findsOneWidget);
    expect(find.text('进行中的目标：执行官方目标样式核对'), findsOneWidget);
    expect(find.text('13h 51m 6s'), findsOneWidget);
    expect(find.textContaining('250 / 1000 tokens'), findsNothing);
    expect(find.byKey(const Key('goal-pause-running-button')), findsOneWidget);
    expect(
      find.byKey(const Key('goal-running-actions-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('goal-progress-row')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('keeps the authoritative completed plan in the live timeline', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-plan'
      ..activeTurnId = 'turn-plan';
    addTearDown(controller.dispose);
    const event = ServerEvent(
      method: 'item/completed',
      params: {
        'threadId': 'thread-plan',
        'turnId': 'turn-plan',
        'item': {'id': 'plan-item', 'type': 'plan', 'text': '1. 检查协议\n2. 完成实现'},
      },
    );

    controller.handleServerEventForTesting(event);
    controller.handleServerEventForTesting(event);

    final plans = controller.entries.where(
      (entry) => entry.title == '计划' && entry.detail.contains('检查协议'),
    );
    expect(plans, hasLength(1));
  });

  testWidgets('uses a submitted goal as its first prompt and criteria', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer());
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..selectedModelId = 'gpt-test'
      ..modelOptions = const [
        CodexModelOption(
          id: 'gpt-test',
          displayName: 'GPT Test',
          description: '',
          isDefault: true,
        ),
      ];
    final composer = TextEditingController();
    ComposerSubmission? submitted;
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
            onSend: (submission) async {
              submitted = submission;
              return true;
            },
            onQueueSteer: (_) async => true,
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('composer-field')), '实现附件菜单。');
    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-goal-menu-item')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('composer-field')), '完成附件菜单');
    await tester.tap(find.byTooltip('发送任务'));
    await tester.pump();

    expect(submitted?.prompt, '完成附件菜单');
    expect(submitted?.goal, '完成附件菜单');
    expect(find.byKey(const Key('composer-goal-chip')), findsNothing);
  });

  testWidgets('uses a goal as the task prompt when no draft preceded it', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    final composer = TextEditingController();
    ComposerSubmission? submitted;
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
            onSend: (submission) async {
              submitted = submission;
              return true;
            },
            onQueueSteer: (_) async => true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-goal-menu-item')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('composer-field')), '优化任务列表');
    await tester.tap(find.byTooltip('发送任务'));
    await tester.pump();

    expect(submitted?.prompt, '优化任务列表');
    expect(submitted?.goal, '优化任务列表');
  });

  testWidgets('accepts the official inline plan slash command', (tester) async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server);
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..selectedModelId = 'gpt-test'
      ..modelOptions = const [
        CodexModelOption(
          id: 'gpt-test',
          displayName: 'GPT Test',
          description: '',
          isDefault: true,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      '/plan 先检查协议再给出实施方案',
    );
    await tester.tap(find.byTooltip('发送任务'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(server.startedTurnPrompt, '先检查协议再给出实施方案');
    expect(server.startedTurnCollaborationMode?['mode'], 'plan');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('accepts the official inline goal slash command', (tester) async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      '/goal 完成协议和界面复刻',
    );
    await tester.tap(find.byTooltip('发送任务'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(server.startedTurnPrompt, '完成协议和界面复刻');
    expect(server.threadGoal, '完成协议和界面复刻');
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'sends goals, plan mode, and structured skill input to App Server',
    () async {
      final server = FakeCodexAppServer();
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..selectedModelId = 'gpt-test'
        ..modelOptions = const [
          CodexModelOption(
            id: 'gpt-test',
            displayName: 'GPT Test',
            description: '',
            isDefault: true,
          ),
        ];

      await controller.sendPrompt(
        r'$documents 实现这个功能',
        goal: '完成附件菜单',
        planMode: true,
        additionalInput: const [
          {
            'type': 'skill',
            'name': 'documents',
            'path': '/skills/documents/SKILL.md',
          },
        ],
      );

      expect(server.threadGoal, '完成附件菜单');
      expect(server.startedTurnPrompt, contains(r'$documents'));
      expect(server.startedTurnAdditionalInput, [
        {
          'type': 'skill',
          'name': 'documents',
          'path': '/skills/documents/SKILL.md',
        },
      ]);
      expect(server.startedTurnCollaborationMode?['mode'], 'plan');
      controller.dispose();
    },
  );

  test(
    'does not roll back an accepted goal turn when list refresh fails',
    () async {
      final server = FakeCodexAppServer()
        ..listThreadsError = StateError('list unavailable');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      expect(await controller.sendPrompt('执行目标', goal: '完成目标'), isTrue);
      expect(controller.isThreadRunning('new-thread'), isTrue);
      expect(server.startedTurnPrompt, '执行目标');
      controller.dispose();
    },
  );

  test('tracks structured plan updates for the active turn', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'turn': {'id': 'turn-1'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-1',
          'explanation': '先核对协议，再实现界面。',
          'plan': [
            {'step': '核对协议', 'status': 'completed'},
            {'step': '实现界面', 'status': 'inProgress'},
            {'step': '运行验证', 'status': 'pending'},
          ],
        },
      ),
    );

    expect(controller.activeTurnId, 'turn-1');
    expect(controller.activeTaskPlan?.explanation, '先核对协议，再实现界面。');
    expect(controller.activeTaskPlan?.focusedStepIndex, 1);
    expect(controller.activeTaskPlan?.completedStepCount, 1);
    expect(
      controller.activeTaskPlan?.steps[1].status,
      TaskPlanStepStatus.inProgress,
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'older-turn',
          'plan': [
            {'step': '迟到的旧计划', 'status': 'inProgress'},
          ],
        },
      ),
    );
    expect(controller.activeTaskPlan?.steps.first.step, '核对协议');
    controller.dispose();
  });

  testWidgets('shows live task steps in a floating progress panel', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-1',
          'explanation': '正在按计划实现分步展示',
          'plan': [
            {'step': '更新文档', 'status': 'completed'},
            {'step': '实现进度面板', 'status': 'inProgress'},
            {'step': '运行测试', 'status': 'pending'},
          ],
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('task-plan-progress')), findsOneWidget);
    expect(find.text('正在按计划实现分步展示'), findsOneWidget);
    expect(find.text('更新文档'), findsOneWidget);
    expect(find.text('实现进度面板'), findsOneWidget);
    expect(find.text('运行测试'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('第 2 / 3 步'), findsOneWidget);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'id': 'turn-1', 'status': 'completed'},
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('task-plan-progress')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the thinking loader attached to a short task plan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-short',
          'plan': [
            {'step': '修复定位', 'status': 'inProgress'},
          ],
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();

    final loader = find.byKey(const Key('live-thinking-loader'));
    final plan = find.byKey(const Key('task-plan-progress'));
    expect(loader, findsOneWidget);
    expect(plan, findsOneWidget);
    final gap = tester.getTopLeft(plan).dy - tester.getBottomLeft(loader).dy;
    expect(gap, inInclusiveRange(11, 13));
    expect(tester.getTopLeft(loader).dy, greaterThanOrEqualTo(0));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scrolls a long task plan to the newly focused step', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running;
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-long',
          'plan': List.generate(
            12,
            (index) => {
              'step': '计划步骤 ${index + 1}',
              'status': index == 0 ? 'inProgress' : 'pending',
            },
          ),
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    // A live turn includes the intentionally repeating thinking indicator.
    await tester.pump();

    final planScrollable = find.descendant(
      of: find.byKey(const Key('task-plan-progress')),
      matching: find.byType(Scrollable),
    );
    expect(planScrollable, findsOneWidget);
    expect(tester.state<ScrollableState>(planScrollable).position.pixels, 0);

    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-long',
          'plan': List.generate(
            12,
            (index) => {
              'step': '计划步骤 ${index + 1}',
              'status': index < 9
                  ? 'completed'
                  : index == 9
                  ? 'inProgress'
                  : 'pending',
            },
          ),
        },
      ),
    );
    // Wait for the plan's scroll transition without waiting on the deliberate
    // looping thinking indicator for this active turn.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('第 10 / 12 步'), findsOneWidget);
    expect(
      tester.state<ScrollableState>(planScrollable).position.pixels,
      greaterThan(0),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
