import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/pending_user_input.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_input_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_plan_implementation_panel.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_fakes/fake_codex_app_server.dart';
import 'widget_fakes/fake_runtime_configuration_store.dart';

void main() {
  test('parses the current App Server request_user_input schema', () {
    final request = PendingUserInputRequest.fromEvent(
      const ServerEvent(
        method: 'item/tool/requestUserInput',
        requestId: 'question-request',
        params: {
          'threadId': 'thread-plan',
          'turnId': 'turn-plan',
          'itemId': 'item-question',
          'isBlocking': true,
          'questions': [
            {
              'id': 'scope',
              'header': '范围',
              'question': '这次改动覆盖哪些平台？',
              'isOther': true,
              'options': [
                {'label': '全部', 'description': '同时覆盖所有桌面平台'},
                {'label': 'macOS', 'description': '仅处理 macOS'},
                {'label': '稍后决定', 'description': ''},
              ],
            },
          ],
        },
      ),
    );

    expect(request, isNotNull);
    expect(request!.questions.single.options.length, 3);
    expect(request.questions.single.options.last.description, isEmpty);
    expect(request.questions.single.allowsOther, isTrue);
  });

  test('rejects malformed request_user_input payloads', () {
    const malformed = ServerEvent(
      method: 'item/tool/requestUserInput',
      requestId: 'bad-question-request',
      params: {
        'threadId': 'thread-plan',
        'turnId': 'turn-plan',
        'itemId': 'item-question',
        'questions': [
          {'id': 'scope', 'header': '范围', 'question': '选择范围'},
        ],
      },
    );

    expect(PendingUserInputRequest.fromEvent(malformed), isNull);

    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
    );
    addTearDown(controller.dispose);
    controller.handleServerEventForTesting(malformed);

    expect(controller.pendingUserInput, isNull);
    expect(writes.single['id'], 'bad-question-request');
    expect(writes.single['error'], isA<Map>());
  });

  testWidgets('lists Plan as a slash command and toggles bare /plan', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(find.byKey(const Key('composer-field')), '/');
    await tester.pump();
    expect(find.text('计划模式'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('composer-field')), '/plan');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(find.byTooltip('发送任务'));
    await tester.pump();

    expect(find.byKey(const Key('composer-plan-mode-chip')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('uses the runtime-advertised Plan mode preset', () async {
    final server = FakeCodexAppServer()
      ..collaborationModeListResponse = const [
        {
          'name': 'Plan',
          'mode': 'plan',
          'model': 'gpt-plan',
          'reasoning_effort': 'high',
        },
      ];
    final controller = CodexController(server: server);
    addTearDown(controller.dispose);
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = null
      ..requiresOpenaiAuth = false
      ..reasoningEffort = ReasoningEffort.defaultValue
      ..selectedModelId = 'gpt-default'
      ..modelOptions = const [
        CodexModelOption(
          id: 'gpt-default',
          displayName: 'GPT Default',
          description: '',
          isDefault: true,
        ),
      ];
    await controller.refreshCollaborationModesForTesting();

    expect(await controller.sendPrompt('制定方案', planMode: true), isTrue);
    expect(server.startedTurnCollaborationMode, {
      'mode': 'plan',
      'settings': {
        'model': 'gpt-plan',
        'reasoning_effort': 'high',
        'developer_instructions': null,
      },
    });
  });

  test('refreshes collaboration presets when reusing a runtime', () async {
    final first = await Directory.systemTemp.createTemp('plan-first-');
    final second = await Directory.systemTemp.createTemp('plan-second-');
    addTearDown(() => first.delete(recursive: true));
    addTearDown(() => second.delete(recursive: true));
    final server = FakeCodexAppServer()
      ..collaborationModeListResponse = const [
        {
          'name': 'Plan',
          'mode': 'plan',
          'model': 'gpt-plan',
          'reasoning_effort': 'high',
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    addTearDown(controller.dispose);
    await controller.waitForInitialConfiguration();
    controller.workspacePath = await first.resolveSymbolicLinks();
    await controller.refreshCollaborationModesForTesting();
    expect(server.collaborationModeListCalls, 1);

    expect(
      await controller.selectWorkspaceAndReconnect(
        await second.resolveSymbolicLinks(),
        restoreLastThread: false,
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(server.collaborationModeListCalls, 2);
  });

  test('keeps Plan selection per thread and follows runtime settings', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..activeThreadId = 'thread-a';
    addTearDown(controller.dispose);

    controller.setComposerPlanMode(true);
    expect(controller.composerPlanMode, isTrue);

    controller.activeThreadId = 'thread-b';
    expect(controller.composerPlanMode, isFalse);
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/settings/updated',
        params: {
          'threadId': 'thread-b',
          'threadSettings': {
            'collaborationMode': {
              'mode': 'plan',
              'settings': {
                'model': 'gpt-plan',
                'reasoning_effort': 'high',
                'developer_instructions': null,
              },
            },
          },
        },
      ),
    );
    expect(controller.composerPlanMode, isTrue);

    controller.activeThreadId = 'thread-a';
    expect(controller.composerPlanMode, isTrue);
  });

  test('restores Plan selection from thread/resume', () async {
    final server = FakeCodexAppServer()
      ..resumeResult = const {
        'thread': {
          'turns': [
            {
              'id': 'turn-plan',
              'status': 'completed',
              'items': [
                {'type': 'plan', 'text': '# Restored plan'},
              ],
            },
          ],
        },
        'collaborationMode': {
          'mode': 'plan',
          'settings': {
            'model': 'gpt-plan',
            'reasoning_effort': 'high',
            'developer_instructions': null,
          },
        },
      };
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace';
    addTearDown(controller.dispose);
    await controller.waitForInitialConfiguration();
    controller.status = RuntimeStatus.ready;

    await controller.resumeThread(
      const CodexThread(
        id: 'thread-restored',
        preview: 'Plan task',
        createdAt: 1,
        updatedAt: 2,
      ),
    );

    expect(controller.activeThreadId, 'thread-restored');
    expect(controller.composerPlanMode, isTrue);
    expect(controller.pendingPlanImplementation?.turnId, 'turn-plan');
    expect(
      controller.pendingPlanImplementation?.planContent,
      '# Restored plan',
    );
  });

  testWidgets('renders and answers structured Plan mode questions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writes = <JsonMap>[];
    final controller =
        CodexController(server: CodexAppServer(messageSink: writes.add))
          ..workspacePath = '/workspace'
          ..activeThreadId = 'thread-plan'
          ..status = RuntimeStatus.running;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/tool/requestUserInput',
        requestId: 'question-request',
        params: {
          'threadId': 'thread-plan',
          'turnId': 'turn-plan',
          'itemId': 'item-question',
          'isBlocking': true,
          'questions': [
            {
              'id': 'scope',
              'header': '范围',
              'question': '这次改动覆盖哪些平台？',
              'options': [
                {'label': '全部', 'description': '同时覆盖所有桌面平台'},
                {'label': 'macOS', 'description': '仅处理 macOS'},
              ],
            },
            {
              'id': 'note',
              'header': '补充',
              'question': '还有什么需要保留？',
              'options': null,
            },
          ],
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    expect(find.byKey(const Key('user-input-panel')), findsOneWidget);
    expect(find.byKey(const Key('user-input-dismiss')), findsOneWidget);
    expect(find.byKey(const Key('user-input-question-scope')), findsOneWidget);
    expect(find.text('范围'), findsNothing);
    expect(find.text('这次改动覆盖哪些平台？'), findsOneWidget);
    expect(find.text('还有什么需要保留？'), findsNothing);
    expect(find.byKey(const Key('user-input-submit')), findsNothing);

    await tester.tap(find.byKey(const Key('user-input-option-scope-全部')));
    await tester.pump(const Duration(milliseconds: 181));
    expect(find.text('还有什么需要保留？'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('user-input-text-note')),
      '保留键盘操作',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('user-input-submit')));
    await tester.tap(find.byKey(const Key('user-input-submit')));
    await tester.pump();

    expect(writes.single, {
      'id': 'question-request',
      'result': {
        'answers': {
          'scope': {
            'answers': ['全部'],
          },
          'note': {
            'answers': ['保留键盘操作'],
          },
        },
      },
    });
    expect(find.byKey(const Key('user-input-panel')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual advance cancels delayed option advance', (tester) async {
    final writes = <JsonMap>[];
    final controller =
        CodexController(server: CodexAppServer(messageSink: writes.add))
          ..workspacePath = '/workspace'
          ..activeThreadId = 'thread-plan'
          ..status = RuntimeStatus.running;
    controller.handleServerEventForTesting(
      _userInputEvent('request-manual-advance', questionCount: 2),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('user-input-option-scope-全部')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 181));

    expect(find.textContaining('较长问题 2'), findsOneWidget);
    expect(writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('secret answers disable keyboard learning and suggestions', (
    tester,
  ) async {
    final request = PendingUserInputRequest.fromEvent(
      const ServerEvent(
        method: 'item/tool/requestUserInput',
        requestId: 'secret-request',
        params: {
          'threadId': 'thread-plan',
          'turnId': 'turn-plan',
          'itemId': 'item-secret',
          'isBlocking': true,
          'questions': [
            {
              'id': 'secret',
              'header': '密钥',
              'question': '请输入密钥',
              'isSecret': true,
              'options': null,
            },
          ],
        },
      ),
    )!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserInputPanel(
            request: request,
            taskLabel: null,
            enabled: true,
            onSubmit: (_, _) async {},
            onDismiss: () async {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('user-input-text-secret')),
    );
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
  });

  test('serverRequest/resolved removes a pending user-input request', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..activeThreadId = 'thread-plan';
    addTearDown(controller.dispose);
    controller.handleServerEventForTesting(_userInputEvent('request-1'));
    expect(controller.pendingUserInput, isNotNull);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'serverRequest/resolved',
        params: {'requestId': 'request-1'},
      ),
    );

    expect(controller.pendingUserInput, isNull);
    expect(controller.shouldShowPendingUserInput, isFalse);
  });

  test('dismisses a non-blocking question with an empty response', () async {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
    )..activeThreadId = 'thread-plan';
    addTearDown(controller.dispose);
    controller.handleServerEventForTesting(
      _userInputEvent('request-dismiss', isBlocking: false),
    );

    await controller.dismissUserInput();

    expect(writes.single, {
      'id': 'request-dismiss',
      'result': {'answers': <String, dynamic>{}},
    });
    expect(controller.pendingUserInput, isNull);
  });

  testWidgets(
    'foreground non-blocking input waits for inactivity then resolves',
    (tester) async {
      final writes = <JsonMap>[];
      final controller =
          CodexController(
              server: CodexAppServer(messageSink: writes.add),
              userInputForegroundInactivityDuration: const Duration(
                milliseconds: 30,
              ),
              userInputAutoResolutionDuration: const Duration(milliseconds: 40),
            )
            ..workspacePath = '/workspace'
            ..activeThreadId = 'thread-plan'
            ..status = RuntimeStatus.running;
      controller.handleServerEventForTesting(
        _userInputEvent('request-timeout', isBlocking: false),
      );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      await tester.pump(const Duration(milliseconds: 31));
      expect(controller.pendingUserInputAutoResolutionDeadline, isNotNull);
      expect(
        find.byKey(const Key('user-input-dismiss-countdown')),
        findsOneWidget,
      );
      expect(writes, isEmpty);
      await tester.pump(const Duration(milliseconds: 41));

      expect(writes.single, {
        'id': 'request-timeout',
        'result': {'answers': <String, dynamic>{}},
      });
      expect(controller.pendingUserInput, isNull);
    },
  );

  testWidgets('answering snoozes non-blocking auto-resolution', (tester) async {
    final writes = <JsonMap>[];
    final controller =
        CodexController(
            server: CodexAppServer(messageSink: writes.add),
            userInputForegroundInactivityDuration: const Duration(
              milliseconds: 20,
            ),
            userInputAutoResolutionDuration: const Duration(milliseconds: 30),
          )
          ..workspacePath = '/workspace'
          ..activeThreadId = 'thread-plan'
          ..status = RuntimeStatus.running;
    controller.handleServerEventForTesting(
      _userInputEvent('request-snooze', isBlocking: false),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('user-input-option-scope-全部')));
    await tester.pump(const Duration(milliseconds: 80));

    expect(writes, isEmpty);
    expect(controller.pendingUserInput, isNotNull);
  });

  testWidgets(
    'background non-blocking input starts its countdown immediately',
    (tester) async {
      final writes = <JsonMap>[];
      final controller = CodexController(
        server: CodexAppServer(messageSink: writes.add),
        userInputForegroundInactivityDuration: const Duration(milliseconds: 80),
        userInputAutoResolutionDuration: const Duration(milliseconds: 30),
      )..activeThreadId = 'foreground';
      addTearDown(controller.dispose);
      controller.setUserInputSurfaceState(
        foregrounded: true,
        presentedThreadId: 'foreground',
      );
      controller.handleServerEventForTesting(
        _userInputEvent(
          'background-timeout',
          threadId: 'background',
          isBlocking: false,
        ),
      );

      await tester.pump(const Duration(milliseconds: 31));

      expect(writes.single, {
        'id': 'background-timeout',
        'result': {'answers': <String, dynamic>{}},
      });
    },
  );

  testWidgets('foreground activity restarts the inactivity window', (
    tester,
  ) async {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
      userInputForegroundInactivityDuration: const Duration(milliseconds: 40),
      userInputAutoResolutionDuration: const Duration(milliseconds: 30),
    )..activeThreadId = 'thread-plan';
    addTearDown(controller.dispose);
    controller.setUserInputSurfaceState(
      foregrounded: true,
      presentedThreadId: 'thread-plan',
    );
    controller.handleServerEventForTesting(
      _userInputEvent('activity-timeout', isBlocking: false),
    );

    await tester.pump(const Duration(milliseconds: 30));
    controller.recordUserInputConversationActivity();
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.pendingUserInputAutoResolutionDeadline, isNull);
    expect(writes, isEmpty);

    await tester.pump(const Duration(milliseconds: 11));
    expect(controller.pendingUserInputAutoResolutionDeadline, isNotNull);
    await tester.pump(const Duration(milliseconds: 31));
    expect(writes.single['id'], 'activity-timeout');
  });

  test('keeps request arrival order while preferring the active task', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..activeThreadId = 'foreground';
    addTearDown(controller.dispose);
    controller.handleServerEventForTesting(
      _userInputEvent('background-first', threadId: 'background'),
    );
    controller.handleServerEventForTesting(
      _userInputEvent('foreground-second', threadId: 'foreground'),
    );

    expect(controller.pendingUserInput?.requestId, 'foreground-second');
    expect(controller.pendingUserInputTaskLabel, isNull);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'serverRequest/resolved',
        params: {'requestId': 'foreground-second'},
      ),
    );
    expect(controller.pendingUserInput?.requestId, 'background-first');
    expect(controller.pendingUserInputTaskLabel, startsWith('后台任务'));
  });

  testWidgets('rejects bare /plan while a turn is running', (tester) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..activeThreadId = 'thread-plan'
      ..activeTurnId = 'turn-plan'
      ..status = RuntimeStatus.running;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(find.byKey(const Key('composer-field')), '/plan');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.byKey(const Key('composer-plan-mode-chip')), findsNothing);
    expect(find.text('任务运行时无法切换计划模式。'), findsOneWidget);
  });

  testWidgets('question card remains usable in a narrow short window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final request = PendingUserInputRequest.fromEvent(
      _userInputEvent('request-narrow', questionCount: 3),
    )!;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserInputPanel(
            request: request,
            taskLabel: null,
            enabled: true,
            onSubmit: (_, _) async {},
            onDismiss: () async => dismissed = true,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('user-input-scroll')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.textContaining('较长问题 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(dismissed, isTrue);
    await tester.ensureVisible(find.byKey(const Key('user-input-dismiss')));
    expect(find.byKey(const Key('user-input-dismiss')), findsOneWidget);
  });

  test(
    'offers a completed Plan once and implements it in default mode',
    () async {
      final server = FakeCodexAppServer()
        ..collaborationModeListResponse = const [
          {'name': 'Default', 'mode': 'default'},
          {'name': 'Plan', 'mode': 'plan'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..activeThreadId = 'thread-plan'
        ..status = RuntimeStatus.ready;
      addTearDown(controller.dispose);
      await controller.waitForInitialConfiguration();
      await controller.refreshCollaborationModesForTesting();
      controller
        ..workspacePath = '/workspace'
        ..activeThreadId = 'thread-plan'
        ..status = RuntimeStatus.ready
        ..requiresOpenaiAuth = false
        ..reasoningEffort = ReasoningEffort.defaultValue
        ..selectedModelId = 'gpt-default'
        ..modelOptions = const [
          CodexModelOption(
            id: 'gpt-default',
            displayName: 'GPT Default',
            description: '',
            isDefault: true,
          ),
        ];
      controller.setComposerPlanMode(true);
      controller
        ..activeTurnId = 'turn-plan'
        ..status = RuntimeStatus.running;

      controller.handleServerEventForTesting(_planItemCompletedEvent());
      controller.handleServerEventForTesting(_planTurnCompletedEvent());
      final request = controller.pendingPlanImplementation;
      expect(request?.planContent, '# The plan\n\n1. Build it');

      controller.handleServerEventForTesting(_planItemCompletedEvent());
      controller.handleServerEventForTesting(_planTurnCompletedEvent());
      expect(controller.pendingPlanImplementation, same(request));

      server.startTurnError = StateError('turn unavailable');
      await controller.implementCompletedPlan(
        threadId: 'thread-plan',
        turnId: 'turn-plan',
      );
      expect(controller.pendingPlanImplementation, same(request));

      server.startTurnError = null;
      await controller.implementCompletedPlan(
        threadId: 'thread-plan',
        turnId: 'turn-plan',
      );

      expect(controller.pendingPlanImplementation, isNull);
      expect(controller.composerPlanMode, isFalse);
      expect(
        server.startedTurnPrompt,
        'PLEASE IMPLEMENT THIS PLAN:\n# The plan\n\n1. Build it',
      );
      expect(server.startedTurnCollaborationMode?['mode'], 'default');
    },
  );

  test(
    'plan feedback stays in Plan mode and dismiss updates next-turn settings',
    () async {
      final server = FakeCodexAppServer()
        ..collaborationModeListResponse = const [
          {'name': 'Default', 'mode': 'default'},
          {'name': 'Plan', 'mode': 'plan'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..activeThreadId = 'thread-plan'
        ..status = RuntimeStatus.ready;
      addTearDown(controller.dispose);
      await controller.waitForInitialConfiguration();
      await controller.refreshCollaborationModesForTesting();
      controller
        ..workspacePath = '/workspace'
        ..activeThreadId = 'thread-plan'
        ..status = RuntimeStatus.ready
        ..requiresOpenaiAuth = false
        ..reasoningEffort = ReasoningEffort.defaultValue
        ..selectedModelId = 'gpt-default'
        ..modelOptions = const [
          CodexModelOption(
            id: 'gpt-default',
            displayName: 'GPT Default',
            description: '',
            isDefault: true,
          ),
        ];
      controller.setComposerPlanMode(true);
      controller
        ..activeTurnId = 'turn-plan'
        ..status = RuntimeStatus.running;
      controller.handleServerEventForTesting(_planItemCompletedEvent());
      controller.handleServerEventForTesting(_planTurnCompletedEvent());

      await controller.submitCompletedPlanFeedback(
        'Add rollback tests',
        threadId: 'thread-plan',
        turnId: 'turn-plan',
      );
      expect(server.startedTurnPrompt, 'Add rollback tests');
      expect(server.startedTurnCollaborationMode?['mode'], 'plan');

      controller
        ..activeTurnId = 'turn-plan-2'
        ..status = RuntimeStatus.running;
      controller.handleServerEventForTesting(
        _planItemCompletedEvent(turnId: 'turn-plan-2'),
      );
      controller.handleServerEventForTesting(
        _planTurnCompletedEvent(turnId: 'turn-plan-2'),
      );
      final dismissCompleter = Completer<void>();
      server
        ..updateThreadSettingsCompleter = dismissCompleter
        ..updateThreadSettingsError = StateError('settings unavailable');
      final failedDismiss = controller.dismissCompletedPlan(
        threadId: 'thread-plan',
        turnId: 'turn-plan-2',
      );
      controller.activeThreadId = 'other-thread';
      dismissCompleter.complete();
      await failedDismiss;
      expect(controller.lastError, isNull);
      expect(
        controller.entries.where(
          (entry) => entry.title == 'Could not dismiss plan',
        ),
        isEmpty,
      );

      controller.activeThreadId = 'thread-plan';
      server
        ..updateThreadSettingsCompleter = null
        ..updateThreadSettingsError = null;
      await controller.dismissCompletedPlan(
        threadId: 'thread-plan',
        turnId: 'turn-plan-2',
      );

      expect(server.updatedSettingsThreadId, 'thread-plan');
      expect(server.updatedSettingsCollaborationMode?['mode'], 'default');
      expect(controller.composerPlanMode, isFalse);
      expect(controller.pendingPlanImplementation, isNull);
    },
  );

  test(
    'keeps a background completed Plan bound to its owning thread',
    () async {
      final server = FakeCodexAppServer()
        ..collaborationModeListResponse = const [
          {'name': 'Plan', 'mode': 'plan'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      addTearDown(controller.dispose);
      await controller.waitForInitialConfiguration();
      await controller.refreshCollaborationModesForTesting();
      controller
        ..workspacePath = '/workspace'
        ..activeThreadId = null
        ..status = RuntimeStatus.ready
        ..requiresOpenaiAuth = false
        ..reasoningEffort = ReasoningEffort.defaultValue
        ..selectedModelId = 'gpt-default'
        ..modelOptions = const [
          CodexModelOption(
            id: 'gpt-default',
            displayName: 'GPT Default',
            description: '',
            isDefault: true,
          ),
        ];
      expect(await controller.sendPrompt('Plan it', planMode: true), isTrue);
      controller
        ..activeThreadId = 'foreground-thread'
        ..status = RuntimeStatus.ready;

      controller.handleServerEventForTesting(
        _planItemCompletedEvent(threadId: 'new-thread'),
      );
      controller.handleServerEventForTesting(
        _planTurnCompletedEvent(threadId: 'new-thread'),
      );
      expect(controller.pendingPlanImplementation, isNull);

      controller.activeThreadId = 'new-thread';
      expect(controller.pendingPlanImplementation?.threadId, 'new-thread');
    },
  );

  test(
    'does not offer failed Plans or execute a request after switching threads',
    () async {
      final server = FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..activeThreadId = 'thread-plan'
        ..status = RuntimeStatus.ready;
      addTearDown(controller.dispose);
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '/workspace'
        ..activeThreadId = 'thread-plan'
        ..status = RuntimeStatus.ready;
      controller.setComposerPlanMode(true);
      controller
        ..activeTurnId = 'turn-failed'
        ..status = RuntimeStatus.running;
      controller.handleServerEventForTesting(
        _planItemCompletedEvent(turnId: 'turn-failed'),
      );
      controller.handleServerEventForTesting(
        _planTurnCompletedEvent(turnId: 'turn-failed', status: 'failed'),
      );
      controller.handleServerEventForTesting(
        _planItemCompletedEvent(turnId: 'turn-failed'),
      );
      expect(controller.pendingPlanImplementation, isNull);

      controller
        ..activeTurnId = 'turn-success'
        ..status = RuntimeStatus.running;
      controller.handleServerEventForTesting(
        _planItemCompletedEvent(turnId: 'turn-success'),
      );
      controller.handleServerEventForTesting(
        _planTurnCompletedEvent(turnId: 'turn-success'),
      );
      expect(controller.pendingPlanImplementation, isNotNull);
      controller.activeThreadId = 'other-thread';

      await controller.implementCompletedPlan(
        threadId: 'thread-plan',
        turnId: 'turn-success',
      );
      expect(server.startedTurnPrompt, isNull);
      controller.activeThreadId = 'thread-plan';
      expect(controller.pendingPlanImplementation, isNotNull);
    },
  );

  testWidgets(
    'completed Plan card supports feedback, keyboard dismissal, and narrow windows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 420));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var feedback = '';
      var implemented = false;
      var dismissed = false;
      const request = PendingPlanImplementationRequest(
        threadId: 'thread-plan',
        turnId: 'turn-plan',
        planContent: '# Plan',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlanImplementationPanel(
              request: request,
              enabled: true,
              onImplement: () async => implemented = true,
              onFeedback: (value) async => feedback = value,
              onDismiss: () async => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.text('Implement this plan?'), findsOneWidget);
      expect(find.text('Yes, implement this plan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Other'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('user-input-text-implement-plan')),
        'Use a smaller patch',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('user-input-submit')));
      await tester.pump();
      expect(feedback, 'Use a smaller patch');
      await tester.enterText(
        find.byKey(const ValueKey('user-input-text-implement-plan')),
        PlanImplementationPanel.implementOption,
      );
      await tester.tap(find.byKey(const Key('user-input-submit')));
      await tester.pump();
      expect(feedback, PlanImplementationPanel.implementOption);
      expect(implemented, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dismissed, isTrue);
    },
  );
}

ServerEvent _planItemCompletedEvent({
  String threadId = 'thread-plan',
  String turnId = 'turn-plan',
}) => ServerEvent(
  method: 'item/completed',
  params: {
    'threadId': threadId,
    'turnId': turnId,
    'item': {
      'id': 'plan-$turnId',
      'type': 'plan',
      'text': '# The plan\n\n1. Build it',
    },
  },
);

ServerEvent _planTurnCompletedEvent({
  String threadId = 'thread-plan',
  String turnId = 'turn-plan',
  String status = 'completed',
}) => ServerEvent(
  method: 'turn/completed',
  params: {
    'threadId': threadId,
    'turnId': turnId,
    'turn': {'id': turnId, 'status': status, 'items': <JsonMap>[]},
  },
);

ServerEvent _userInputEvent(
  String requestId, {
  String threadId = 'thread-plan',
  bool isBlocking = true,
  int questionCount = 1,
}) => ServerEvent(
  method: 'item/tool/requestUserInput',
  requestId: requestId,
  params: {
    'threadId': threadId,
    'turnId': 'turn-plan',
    'itemId': 'item-question',
    'isBlocking': isBlocking,
    'questions': [
      for (var index = 0; index < questionCount; index++)
        {
          'id': index == 0 ? 'scope' : 'scope-$index',
          'header': '范围 ${index + 1}',
          'question': '这是一个用于验证窄窗口滚动行为的较长问题 ${index + 1}？',
          'options': [
            {'label': '全部', 'description': '覆盖全部目标并保留现有行为'},
            {'label': '部分', 'description': '仅覆盖选定的目标范围'},
          ],
        },
    ],
  },
);
