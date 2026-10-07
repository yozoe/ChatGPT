import 'dart:async';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/task_completion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

CodexThread threadForTest({
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

  testWidgets('renders permission approval as a Codex floating action card', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/permissions/requestApproval',
        requestId: 99,
        params: {
          'threadId': 'thread-approval',
          'reason': '是否允许在工作区之外创建演示文件？',
          'command': 'touch /tmp/codex-approval-demo.txt',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('approval-panel')), findsOneWidget);
    expect(find.text('权限请求'), findsOneWidget);
    expect(find.text('允许一次'), findsOneWidget);
    expect(find.text('拒绝  Esc'), findsOneWidget);
    expect(find.text('touch /tmp/codex-approval-demo.txt'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('approval-panel'))).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('composer-panel'))).top,
      ),
    );

    await tester.tap(find.byKey(const Key('approval-more-options')));
    await tester.pumpAndSettle();
    expect(find.text('允许类似操作'), findsOneWidget);
    await tester.tap(find.text('允许类似操作'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not show a completion reminder for an interrupted task', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'stopped-thread'
      ..threads = [threadForTest(id: 'stopped-thread', status: 'active')];

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'interrupted'},
        },
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('sidebar-completed-task-indicator')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'acknowledges the current task when its timeline is already at the bottom',
    (tester) async {
      const completionChannel = MethodChannel('codex_desk/task_completion');
      final completionCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(completionChannel, (call) async {
        completionCalls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(completionChannel, null),
      );
      final controller =
          CodexController(
              server: CodexAppServer(),
              taskCompletionNotifier: TaskCompletionNotifier(
                channel: completionChannel,
              ),
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.running
            ..activeThreadId = 'current-thread'
            ..threads = [threadForTest(id: 'current-thread', status: 'active')];

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('sidebar-completed-task-indicator')),
        findsNothing,
      );
      expect(find.byKey(const Key('composer-activity-pill')), findsNothing);
      expect(
        controller.isCompletedThreadAcknowledged('current-thread'),
        isTrue,
      );
      expect(
        completionCalls
            .where((call) => call.method == 'setDockBadge')
            .map((call) => call.arguments),
        [
          <String, Object>{'visible': true, 'count': 1},
        ],
      );
      expect(
        completionCalls.where((call) => call.method == 'notifyTaskCompleted'),
        hasLength(1),
      );
      await controller.acknowledgeCompletedThread('current-thread');
      expect(
        completionCalls
            .where((call) => call.method == 'setDockBadge')
            .map((call) => call.arguments),
        [
          <String, Object>{'visible': true, 'count': 1},
          <String, Object>{'visible': false, 'count': 0},
        ],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'clears a completed task Dock badge only when the app resumes to its conversation',
    (tester) async {
      const completionChannel = MethodChannel('codex_desk/task_completion');
      final completionCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(completionChannel, (call) async {
        completionCalls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(completionChannel, null),
      );
      final controller =
          CodexController(
              server: CodexAppServer(),
              taskCompletionNotifier: TaskCompletionNotifier(
                channel: completionChannel,
              ),
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.running
            ..activeThreadId = 'current-thread'
            ..threads = [threadForTest(id: 'current-thread', status: 'active')];

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(controller.hasUnacknowledgedCompletion('current-thread'), isTrue);
      await tester.tap(find.byKey(const Key('sidebar-settings-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-page')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(controller.hasUnacknowledgedCompletion('current-thread'), isTrue);
      expect(
        completionCalls
            .where((call) => call.method == 'setDockBadge')
            .map((call) => call.arguments),
        [
          <String, Object>{'visible': true, 'count': 1},
        ],
      );

      await tester.tap(find.byKey(const Key('settings-back-button')));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(controller.hasUnacknowledgedCompletion('current-thread'), isFalse);
      expect(
        completionCalls
            .where((call) => call.method == 'setDockBadge')
            .map((call) => call.arguments),
        [
          <String, Object>{'visible': true, 'count': 1},
          <String, Object>{'visible': false, 'count': 0},
        ],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keeps the completion reminder above the fold and clears it at the bottom',
    (tester) async {
      final initialEntries = List<TimelineEntry>.generate(
        30,
        (index) => TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '历史消息 $index\n${'内容 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 0, index),
        ),
      );
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'current-thread'
        ..threads = [threadForTest(id: 'current-thread', status: 'active')]
        ..replaceTimelineEntriesForTesting(initialEntries);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump();

      final timelineFinder = find.descendant(
        of: find.byKey(
          const ValueKey('conversation-timeline-/workspace:current-thread'),
        ),
        matching: find.byType(ListView),
      );
      final timeline = tester.widget<ListView>(timelineFinder);
      timeline.controller!.jumpTo(
        timeline.controller!.position.maxScrollExtent,
      );
      await tester.pump();
      await tester.drag(timelineFinder, const Offset(0, 360));
      await tester.pump();
      expect(timeline.controller!.position.extentAfter, greaterThan(48));
      double timelineBottomPadding() {
        final padding = tester.widget<ListView>(timelineFinder).padding;
        return (padding! as EdgeInsets).bottom;
      }

      final runningBottomPadding = timelineBottomPadding();

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        controller.isCompletedThreadAcknowledged('current-thread'),
        isFalse,
      );
      expect(
        find.byKey(const Key('sidebar-completed-task-indicator')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('composer-activity-pill')), findsOneWidget);
      expect(timelineBottomPadding(), runningBottomPadding);

      await tester.drag(timelineFinder, const Offset(0, -10000));
      await tester.pumpAndSettle();

      expect(timeline.controller!.position.extentAfter, lessThanOrEqualTo(48));
      expect(
        controller.isCompletedThreadAcknowledged('current-thread'),
        isTrue,
      );
      expect(
        find.byKey(const Key('sidebar-completed-task-indicator')),
        findsNothing,
      );
      expect(find.byKey(const Key('composer-activity-pill')), findsNothing);
      expect(timelineBottomPadding(), runningBottomPadding);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'clears the completion reminder when resizing reveals the timeline bottom',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final initialEntries = List<TimelineEntry>.generate(
        16,
        (index) => TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '历史消息 $index\n${'内容 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 0, index),
        ),
      );
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'current-thread'
        ..threads = [threadForTest(id: 'current-thread', status: 'active')]
        ..replaceTimelineEntriesForTesting(initialEntries);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump();

      final timelineFinder = find.descendant(
        of: find.byKey(
          const ValueKey('conversation-timeline-/workspace:current-thread'),
        ),
        matching: find.byType(ListView),
      );
      final timeline = tester.widget<ListView>(timelineFinder);
      timeline.controller!.jumpTo(
        timeline.controller!.position.maxScrollExtent,
      );
      await tester.pump();
      await tester.drag(timelineFinder, const Offset(0, 260));
      await tester.pump();
      expect(timeline.controller!.position.extentAfter, greaterThan(48));

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        controller.isCompletedThreadAcknowledged('current-thread'),
        isFalse,
      );
      expect(find.byKey(const Key('composer-activity-pill')), findsOneWidget);

      await tester.binding.setSurfaceSize(const Size(800, 2600));
      await tester.pumpAndSettle();

      expect(timeline.controller!.position.extentAfter, lessThanOrEqualTo(48));
      expect(
        controller.isCompletedThreadAcknowledged('current-thread'),
        isTrue,
      );
      expect(find.byKey(const Key('composer-activity-pill')), findsNothing);
      expect(
        find.byKey(const Key('sidebar-completed-task-indicator')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'opens another task while the current task continues in the background',
    () async {
      final server = FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'running-thread'
        ..threads = [
          threadForTest(id: 'running-thread', status: 'active'),
          threadForTest(id: 'next-thread'),
        ];

      await controller.resumeThread(threadForTest(id: 'next-thread'));

      expect(server.resumedThreadId, 'next-thread');
      expect(controller.activeThreadId, 'next-thread');
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.isThreadRunning('running-thread'), isTrue);
      expect(controller.canSend, isTrue);
      controller.dispose();
    },
  );

  test(
    'opens a running background task without requesting a second writer',
    () async {
      final server = FakeCodexAppServer()
        ..turnPage = {
          'data': [
            {'id': 'background-turn', 'startedAt': 1, 'items': <JsonMap>[]},
          ],
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread'
        ..activeTurnId = 'background-turn';

      controller.createThread();
      await controller.resumeThread(threadForTest(id: 'background-thread'));

      expect(server.resumedThreadId, isNull);
      expect(server.turnPageCursors, [isNull]);
      expect(controller.activeThreadId, 'background-thread');
      expect(controller.activeTurnId, 'background-turn');
      expect(controller.status, RuntimeStatus.running);
      expect(controller.canSteer, isTrue);

      expect(await controller.steerCurrentTurn('继续，但换一个方向'), isTrue);
      expect(server.steeredTurnThreadId, 'background-thread');
      expect(server.steeredTurnId, 'background-turn');
      controller.dispose();
    },
  );

  test(
    'keeps the running task active when opening another task fails',
    () async {
      final server = FakeCodexAppServer()..resumeError = StateError('offline');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'running-thread'
        ..activeTurnId = 'running-turn';

      await controller.resumeThread(threadForTest(id: 'next-thread'));

      expect(controller.activeThreadId, 'running-thread');
      expect(controller.activeTurnId, 'running-turn');
      expect(controller.status, RuntimeStatus.running);
      expect(controller.isThreadRunning('running-thread'), isTrue);
      controller.dispose();
    },
  );

  testWidgets('allows switching sidebar tasks while another task runs', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running-thread'
      ..threads = [
        threadForTest(id: 'running-thread', status: 'active'),
        threadForTest(id: 'next-thread'),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(
      find.byKey(const ValueKey('sidebar-thread-tile-next-thread')),
    );
    // The background task keeps its progress indicator animating, so the
    // widget tree intentionally never settles while it is still running.
    await tester.pump();
    await tester.pump();

    expect(controller.activeThreadId, 'next-thread');
    expect(controller.isThreadRunning('running-thread'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens current-workspace search results while a task runs', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running-thread'
      ..threads = [
        threadForTest(id: 'running-thread', status: 'active'),
        threadForTest(id: 'other-thread'),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('task-search-button')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('task-search-result-other-thread')),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.activeThreadId, 'other-thread');
    expect(controller.isThreadRunning('running-thread'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('interrupts the active turn with both protocol identifiers', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    expect(controller.canStop, isTrue);
    await controller.stopCurrentTurn();

    expect(server.interruptedThreadId, 'thread-1');
    expect(server.interruptedTurnId, 'turn-1');
    controller.dispose();
  });

  test('does not expose stop before the active turn id is known', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1';

    expect(controller.canStop, isFalse);
    await controller.stopCurrentTurn();
    expect(server.interruptedThreadId, isNull);
    controller.dispose();
  });

  test(
    'does not write a delayed stop result into a newly opened task',
    () async {
      final server = FakeCodexAppServer()
        ..interruptCompleter = Completer<void>();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'stopped-thread'
        ..activeTurnId = 'stopped-turn';

      final stopping = controller.stopCurrentTurn();
      await Future<void>.delayed(Duration.zero);
      controller
        ..activeThreadId = 'new-thread'
        ..activeTurnId = 'new-turn';
      server.interruptCompleter!.complete();
      await stopping;

      expect(
        controller.entries.where((entry) => entry.title == '已请求停止'),
        isEmpty,
      );
      expect(
        controller.entries.where((entry) => entry.title == '停止失败'),
        isEmpty,
      );
      controller.dispose();
    },
  );

  test(
    'treats an identified current-thread completion as current after stale history',
    () {
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'running-thread'
        ..activeTurnId = 'stale-turn'
        ..threads = [threadForTest(id: 'running-thread', status: 'active')];

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'running-thread',
            'turn': {'id': 'actual-turn', 'status': 'completed'},
          },
        ),
      );

      expect(controller.status, RuntimeStatus.ready);
      expect(controller.activeTurnId, isNull);
      expect(controller.isThreadRunning('running-thread'), isFalse);
      controller.dispose();
    },
  );

  test(
    'keeps an in-flight task bound to its original thread after new chat',
    () async {
      final server = FakeCodexAppServer()
        ..queueListRequests = true
        ..startThreadResponseIds.addAll(['thread-a', 'thread-b']);
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      final firstSend = controller.sendPrompt('任务 A');
      await Future<void>.delayed(Duration.zero);
      expect(server.listRequests, hasLength(1));

      controller.createThread();
      final secondSend = controller.sendPrompt('任务 B');
      await Future<void>.delayed(Duration.zero);
      expect(server.listRequests, hasLength(2));

      server.listRequests[0].complete(const []);
      expect(await firstSend, isTrue);
      expect(controller.activeThreadId, 'thread-b');
      expect(controller.status, RuntimeStatus.running);
      expect(server.startedTurnThreadIds, ['thread-a', 'thread-b']);
      expect(
        controller.threads.map((thread) => thread.id),
        containsAll(['thread-a', 'thread-b']),
      );

      server.listRequests[1].complete(const []);
      expect(await secondSend, isTrue);
      expect(server.startedTurnThreadIds, ['thread-a', 'thread-b']);
      controller.dispose();
    },
  );

  test(
    'reconciles an unscoped completion after refreshing background tasks',
    () async {
      final server = FakeCodexAppServer()..queueListRequests = true;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread';
      controller.createThread();
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'foreground-thread'
        ..activeTurnId = 'foreground-turn';

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(server.listRequests, hasLength(1));
      server.listRequests.single.complete([
        {'id': 'background-thread', 'preview': 'background', 'status': 'idle'},
        {
          'id': 'foreground-thread',
          'preview': 'foreground',
          'status': 'active',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeThreadId, 'foreground-thread');
      expect(controller.activeTurnId, 'foreground-turn');
      expect(controller.status, RuntimeStatus.running);
      expect(controller.isThreadRunning('background-thread'), isFalse);
      controller.dispose();
    },
  );

  test(
    'keeps an unscoped cancelled background completion acknowledged',
    () async {
      final server = FakeCodexAppServer()..queueListRequests = true;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread';
      controller.createThread();
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'foreground-thread'
        ..activeTurnId = 'foreground-turn';

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'cancelled'},
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      server.listRequests.single.complete([
        {'id': 'background-thread', 'preview': 'background', 'status': 'idle'},
        {
          'id': 'foreground-thread',
          'preview': 'foreground',
          'status': 'active',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.isThreadRunning('background-thread'), isFalse);
      expect(
        controller.isCompletedThreadAcknowledged('background-thread'),
        isTrue,
      );
      controller.dispose();
    },
  );

  test(
    'does not write an unscoped background completion into a new task',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {
            'id': 'background-thread',
            'preview': 'background',
            'status': 'idle',
          },
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread';
      controller.createThread();
      controller.replaceTimelineEntriesForTesting(const []);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeThreadId, isNull);
      expect(
        controller.entries.where((entry) => entry.title == '任务完成'),
        isEmpty,
      );
      expect(controller.isThreadRunning('background-thread'), isFalse);
      controller.dispose();
    },
  );

  test(
    'reconciles an unscoped completion when the focused task is terminal',
    () async {
      final server = FakeCodexAppServer()..queueListRequests = true;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread';
      controller.createThread();
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'foreground-thread'
        ..activeTurnId = 'foreground-turn'
        ..threads = [
          threadForTest(id: 'background-thread', status: 'active'),
          threadForTest(id: 'foreground-thread', status: 'active'),
        ];

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(server.listRequests, hasLength(1));
      server.listRequests.single.complete([
        {
          'id': 'background-thread',
          'preview': 'background',
          'status': 'active',
        },
        {'id': 'foreground-thread', 'preview': 'foreground', 'status': 'idle'},
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, RuntimeStatus.ready);
      expect(controller.activeTurnId, isNull);
      expect(controller.isThreadRunning('foreground-thread'), isFalse);
      expect(
        controller.threads
            .firstWhere((thread) => thread.id == 'foreground-thread')
            .status,
        'idle',
      );
      controller.dispose();
    },
  );

  test(
    'labels an approval from a background task without writing it to the foreground timeline',
    () {
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread'
        ..threads = [threadForTest(id: 'background-thread')];
      controller.createThread();
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'foreground-thread';

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/commandExecution/requestApproval',
          requestId: 'background-approval',
          params: {'threadId': 'background-thread', 'command': 'dart test'},
        ),
      );

      expect(controller.pendingApproval?.requestId, 'background-approval');
      expect(controller.pendingApprovalTaskLabel, 'preview-background-thread');
      expect(
        controller.entries.map((entry) => entry.kind),
        isNot(contains(TimelineKind.approval)),
      );
      controller.dispose();
    },
  );
}
