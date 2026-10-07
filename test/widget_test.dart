import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'widget_test_fakes.dart';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/local_session_thread_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _FakeRuntimeConfigurationStore = FakeRuntimeConfigurationStore;
typedef _MemoryConversationHistoryStore = MemoryConversationHistoryStore;
typedef _MemoryLocalSessionThreadStore = MemoryLocalSessionThreadStore;
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

  testWidgets('shows a hook loading failure instead of a false empty state', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );

    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-nav-钩子')),
      240,
      scrollable: find.descendant(
        of: find.byKey(const Key('settings-navigation-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('settings-nav-钩子')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-hooks-page')), findsOneWidget);
    expect(find.byKey(const Key('settings-hooks-description')), findsOneWidget);
    final hooksErrorState = find.byKey(const Key('settings-hooks-error-state'));
    expect(hooksErrorState, findsOneWidget);
    expect(tester.getSize(hooksErrorState).width, greaterThan(300));
    expect(find.text('无法读取钩子'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-hooks-refresh')));
    await tester.pump();

    expect(find.byKey(const Key('settings-hooks-error-state')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps the active reply on stable text metrics until Markdown completes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'thread-1',
            'turn': {'id': 'turn-1'},
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'streaming-markdown',
            'delta': '第一行',
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump(const Duration(milliseconds: 60));

      final streamingText = find.byKey(const Key('agent-streaming-text'));
      expect(streamingText, findsOneWidget);
      expect(find.byKey(const Key('agent-markdown-selection')), findsNothing);
      final firstTop = tester.getTopLeft(streamingText).dy;
      final textWidget = tester.widget<Text>(streamingText);
      expect(textWidget.strutStyle?.forceStrutHeight, isTrue);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'streaming-markdown',
            'delta': '\n\n- **尚未完成',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(tester.getTopLeft(streamingText).dy, closeTo(firstTop, 0.1));
      expect(find.textContaining('**尚未完成'), findsOneWidget);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'streaming-markdown',
            'delta': '**',
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {'id': 'streaming-markdown', 'type': 'agentMessage'},
          },
        ),
      );
      await tester.pump();

      expect(streamingText, findsNothing);
      expect(find.byKey(const Key('agent-markdown-selection')), findsOneWidget);
      final renderedText = find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('尚未完成'),
      );
      expect(renderedText, findsOneWidget);
      expect(
        tester.widget<RichText>(renderedText).text.toPlainText(),
        isNot(contains('**')),
      );

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keeps ID-less compatible-server deltas on the stable streaming layout',
    (tester) async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-without-turn-id';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {'itemId': 'id-less-stream', 'delta': '- **仍在输出'},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byKey(const Key('agent-streaming-text')), findsOneWidget);
      expect(find.byKey(const Key('agent-markdown-selection')), findsNothing);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {'itemId': 'id-less-stream', 'delta': '**'},
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {'id': 'id-less-stream', 'type': 'agentMessage'},
          },
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('agent-streaming-text')), findsNothing);
      expect(find.byKey(const Key('agent-markdown-selection')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keeps completed turn disclosure state when an earlier entry is inserted',
    (tester) async {
      final controller = CodexController(server: CodexAppServer());
      final command = TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'flutter analyze\nNo issues found',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      );
      final duration = TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 1 秒',
        detail: '',
        createdAt: DateTime(2026, 1, 1, 0, 0, 2),
      );
      controller.replaceTimelineEntriesForTesting([command, duration]);
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      await tester.tap(
        find.byKey(const Key('completed-turn-disclosure-toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text('已运行了命令'), findsNothing);

      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.system,
          title: '迟到的确认',
          detail: '',
          createdAt: DateTime(2026),
        ),
        command,
        duration,
      ]);
      await tester.pump();

      expect(find.text('已运行了命令'), findsNothing);
      expect(
        find.byKey(ValueKey('completed-turn-disclosure-${duration.id}')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('shows App Server context usage without a local estimate', (
    tester,
  ) async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..activeThreadId = 'usage-thread'
      ..activeTurnId = 'usage-turn';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/tokenUsage/updated',
        params: {
          'threadId': 'usage-thread',
          'turnId': 'usage-turn',
          'tokenUsage': {
            'last': {'totalTokens': 25000},
            'total': {'totalTokens': 80000},
            'modelContextWindow': 100000,
          },
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('composer-context-usage-button')));
    await tester.pumpAndSettle();

    expect(find.text('25% 已用（剩余 75%）'), findsOneWidget);
    expect(find.text('已用 25k 标记，共 100k'), findsOneWidget);
    expect(find.textContaining('估算'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  test('new thread discards the first user message from restored history', () {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: '上一个任务的首条消息',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '上一个任务的回复',
        createdAt: DateTime(2026),
      ),
    ]);

    controller.createThread();

    expect(controller.entries, isEmpty);
    expect(
      controller.entries.map((entry) => entry.detail),
      isNot(contains('上一个任务的首条消息')),
    );
    controller.dispose();
  });

  test(
    'classifies server approval requests before JSON-RPC responses',
    () async {
      final server = CodexAppServer();
      final eventFuture = server.events.first;

      server.handleStdoutLineForTesting('''
      {"id": "approval-1", "method": "item/fileChange/requestApproval",
       "params": {"threadId": "thread-1", "turnId": "turn-1"}}
    ''');

      final event = await eventFuture;
      expect(event.isServerRequest, isTrue);
      expect(event.requestId, 'approval-1');
      expect(event.method, 'item/fileChange/requestApproval');
      await server.dispose();
    },
  );

  test('preserves structured App Server errors across requests', () async {
    late CodexAppServer server;
    server = CodexAppServer(
      messageSink: (message) {
        scheduleMicrotask(
          () => server.handleStdoutLineForTesting(
            jsonEncode({
              'id': message['id'],
              'error': {
                'code': 'usage_limit_reached',
                'message': 'localized limit message',
                'data': {'type': 'usage_limit'},
              },
            }),
          ),
        );
      },
    );

    await expectLater(
      server.startTurn(
        threadId: 'thread-1',
        prompt: 'retry later',
        workingDirectory: '/workspace',
      ),
      throwsA(
        isA<CodexAppServerException>()
            .having((error) => error.code, 'code', 'usage_limit_reached')
            .having((error) => error.type, 'type', 'usage_limit')
            .having(
              (error) => error.message,
              'message',
              'localized limit message',
            ),
      ),
    );
    await server.dispose();
  });

  testWidgets('renders filesystem actions and reasoning summaries like Codex', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'read-1',
            'type': 'commandExecution',
            'command': "sed -n '1,80p' test/app_shell_test.dart",
            'commandActions': [
              {
                'type': 'read',
                'command': "sed -n '1,80p' test/app_shell_test.dart",
                'name': 'app_shell_test.dart',
                'path': 'test/app_shell_test.dart',
              },
            ],
          },
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final liveRow = find.byKey(const Key('live-activity-row'));
    expect(find.text('正在读取 app_shell_test.dart'), findsOneWidget);
    expect(
      find.descendant(
        of: liveRow,
        matching: find.byIcon(Icons.menu_book_outlined),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('live-command-row')), findsNothing);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {'id': 'reasoning-1', 'type': 'reasoning', 'summary': []},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/reasoning/summaryTextDelta',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'reasoning-1',
          'summaryIndex': 0,
          'delta': '**Clarifying window merge behavior**',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Clarifying window merge behavior'), findsOneWidget);
    expect(
      find.descendant(of: liveRow, matching: find.byType(Icon)),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('keeps command output delta protocol events out of the timeline', () {
    final controller = CodexController(server: CodexAppServer());
    final initialEntryCount = controller.entries.length;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/commandExecution/outputDelta',
        params: {'itemId': 'command-1', 'delta': 'Compiling...'},
      ),
    );

    expect(controller.entries, hasLength(initialEntryCount));
    expect(controller.entries.where((entry) => entry.title == '执行事件'), isEmpty);
    controller.dispose();
  });

  test(
    'uses the authoritative App Server thread list after reconnecting',
    () async {
      final server = _FakeCodexAppServer()..listResponse = [];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..threads = [_thread(id: 'cached-thread')];

      await controller.refreshThreads();

      expect(controller.threads, isEmpty);
      controller.dispose();
    },
  );

  test(
    'falls back to local Codex sessions when App Server lists none',
    () async {
      final localSessions = _MemoryLocalSessionThreadStore()
        ..threadsByWorkspace['/workspace'] = [_thread(id: 'local-thread')];
      final controller = CodexController(
        server: _FakeCodexAppServer()..listResponse = [],
        localSessionThreadStore: localSessions,
      )..workspacePath = '/workspace';

      await controller.refreshThreads();

      expect(controller.threads.single.id, 'local-thread');
      controller.dispose();
    },
  );

  test('reads a workspace thread from local Codex session metadata', () async {
    final directory = await Directory.systemTemp.createTemp('codex-sessions-');
    addTearDown(() => directory.delete(recursive: true));
    final sessionDirectory = Directory('${directory.path}/2026/08/20');
    await sessionDirectory.create(recursive: true);
    await File('${sessionDirectory.path}/rollout.jsonl').writeAsString(
      '${jsonEncode({
        'type': 'session_meta',
        'payload': {'session_id': 'local-thread', 'timestamp': '2026-08-20T00:00:00.000Z', 'cwd': '/workspace', 'model_provider': 'openai'},
      })}\n',
    );

    final threads = await LocalSessionThreadStore(
      directory: directory,
    ).listThreads('/workspace');

    expect(threads.single.id, 'local-thread');
    expect(threads.single.modelProvider, 'openai');
  });

  test(
    'records every App Server network retry without ending the active turn',
    () {
      final controller = CodexController(server: _FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';

      void reconnecting() {
        controller.handleServerEventForTesting(
          const ServerEvent(
            method: 'error',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'willRetry': true,
              'error': {'message': 'network unavailable'},
            },
          ),
        );
      }

      reconnecting();
      reconnecting();

      final retries = controller.entries
          .where((entry) => entry.activityKind == 'networkRetry')
          .toList();
      expect(retries, hasLength(2));
      expect(
        retries.map((entry) => entry.title),
        everyElement('Reconnecting... waiting for network'),
      );
      expect(retries.map((entry) => entry.activityStatus), [
        'historical',
        'waiting',
      ]);
      expect(retries.map((entry) => entry.sourceItemId).toSet(), hasLength(2));
      expect(controller.status, RuntimeStatus.running);
      expect(controller.canStop, isTrue);
      expect(controller.lastError, isNull);
      expect(controller.hasFailedTurnRetry, isFalse);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'answer-1',
            'delta': '网络恢复后继续',
          },
        ),
      );
      expect(
        controller.entries.any((entry) => entry.detail == '网络恢复后继续'),
        isTrue,
      );
      expect(
        controller.entries
            .where((entry) => entry.activityKind == 'networkRetry')
            .map((entry) => entry.activityStatus),
        everyElement('historical'),
      );

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-1',
            'turn': {'id': 'turn-1', 'status': 'completed'},
          },
        ),
      );
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.hasFailedTurnRetry, isFalse);
      controller.dispose();
    },
  );

  test('ignores non-retrying and incorrectly scoped network errors', () {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    for (final params in <JsonMap>[
      {
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'willRetry': false,
        'error': {'message': 'final failure'},
      },
      {
        'threadId': 'thread-2',
        'turnId': 'turn-1',
        'willRetry': true,
        'error': {'message': 'background retry'},
      },
      {
        'threadId': 'thread-1',
        'turnId': 'turn-2',
        'willRetry': true,
        'error': {'message': 'late retry'},
      },
    ]) {
      controller.handleServerEventForTesting(
        ServerEvent(method: 'error', params: params),
      );
    }

    expect(
      controller.entries.where((entry) => entry.activityKind == 'networkRetry'),
      isEmpty,
    );
    expect(controller.status, RuntimeStatus.running);
    expect(controller.lastError, isNull);
    controller.dispose();
  });

  test(
    'restores a background task network retry in its own timeline',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'new-thread', 'preview': 'background', 'status': 'active'},
        ]
        ..turnPage = {
          'data': [
            {'id': 'turn-1', 'status': 'inProgress', 'items': <JsonMap>[]},
          ],
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      expect(await controller.sendPrompt('后台任务'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'new-thread',
            'turn': {'id': 'turn-1'},
          },
        ),
      );
      controller.createThread();

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'error',
          params: {
            'threadId': 'new-thread',
            'turnId': 'turn-1',
            'willRetry': true,
            'error': {'message': 'offline'},
          },
        ),
      );
      expect(
        controller.entries.where(
          (entry) => entry.activityKind == 'networkRetry',
        ),
        isEmpty,
      );

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'new-thread',
            'turnId': 'turn-1',
            'itemId': 'answer-1',
            'delta': '恢复后的后台回复',
          },
        ),
      );
      await controller.resumeThread(
        _thread(id: 'new-thread', status: 'active'),
      );

      final retry = controller.entries.singleWhere(
        (entry) => entry.activityKind == 'networkRetry',
      );
      expect(retry.title, 'Reconnecting... waiting for network');
      expect(retry.activityStatus, 'historical');
      expect(controller.activeThreadId, 'new-thread');
      expect(controller.activeTurnId, 'turn-1');
      controller.dispose();
    },
  );

  testWidgets('renders retryable network errors like the Codex timeline', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'error',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'willRetry': true,
          'error': {'message': 'offline'},
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('network-retry-activity')), findsOneWidget);
    expect(find.byKey(const Key('network-retry-icon')), findsOneWidget);
    expect(find.text('Reconnecting... waiting for network'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byKey(const Key('network-retry-icon'))).icon,
      Icons.wifi,
    );
    expect(find.byKey(const Key('failed-turn-retry-notice')), findsNothing);

    final retryEntry = controller.entries.singleWhere(
      (entry) => entry.activityKind == 'networkRetry',
    );
    final retrySemantics = find.byKey(
      ValueKey('conversation-activity-${retryEntry.sourceItemId}'),
    );
    expect(
      tester.widget<Semantics>(retrySemantics).properties.liveRegion,
      isTrue,
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'answer-1',
          'delta': 'continued',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<Semantics>(retrySemantics).properties.liveRegion,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
