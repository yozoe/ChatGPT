import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/relay_provider_configuration.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/relay_provider_store.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedRelayProviderStore extends RelayProviderStore {
  final completer = Completer<RelayProviderConfiguration?>();

  @override
  Future<RelayProviderConfiguration?> read() => completer.future;
}

class _EmptyRelayProviderStore extends RelayProviderStore {
  @override
  Future<RelayProviderConfiguration?> read() async => null;
}

class _FakeRuntimeConfigurationStore extends RuntimeConfigurationStore {
  String? workspace;
  String? savedWorkspace;
  String? reasoningEffort;
  String? savedReasoningEffort;
  bool clearedWorkspace = false;

  @override
  Future<String?> readExecutable() async => null;

  @override
  Future<String?> readWorkspace() async => workspace;

  @override
  Future<void> saveWorkspace(String value) async {
    savedWorkspace = value;
    workspace = value;
  }

  @override
  Future<void> clearWorkspace() async {
    clearedWorkspace = true;
    workspace = null;
  }

  @override
  Future<String?> readReasoningEffort() async => reasoningEffort;

  @override
  Future<void> saveReasoningEffort(String? value) async {
    savedReasoningEffort = value;
    reasoningEffort = value;
  }
}

class _FakeCodexAppServer extends CodexAppServer {
  _FakeCodexAppServer() : super(executable: '/not/a/codex');

  final listRequests = <Completer<List<JsonMap>>>[];
  List<JsonMap> listResponse = <JsonMap>[];
  List<JsonMap> archivedListResponse = <JsonMap>[];
  bool queueListRequests = false;
  Object? resumeError;
  JsonMap resumeResult = {
    'thread': {'turns': <JsonMap>[]},
  };
  JsonMap turnPage = {'data': <JsonMap>[]};
  final turnPageCursors = <String?>[];
  JsonMap itemPage = {'data': <JsonMap>[]};
  final itemPageTurnIds = <String>[];
  Object? itemPageError;
  List<JsonMap>? itemPages;
  var itemPageIndex = 0;
  String? resumedThreadId;
  String? resumedModelProvider;
  String? resumedModel;
  JsonMap? resumedConfig;
  String? startedThreadDirectory;
  String? startedModelProvider;
  String? startedModel;
  JsonMap? startedConfig;
  String? unarchivedThreadId;
  int unarchiveCalls = 0;
  Completer<void>? unarchiveCompleter;

  @override
  bool get isRunning => true;

  @override
  Future<List<JsonMap>> listThreads({
    required String workingDirectory,
    bool archived = false,
  }) {
    if (archived) return Future.value(archivedListResponse);
    if (!queueListRequests) return Future.value(listResponse);
    final completer = Completer<List<JsonMap>>();
    listRequests.add(completer);
    return completer.future;
  }

  @override
  Future<JsonMap> resumeThread({
    required String threadId,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    resumedThreadId = threadId;
    resumedModelProvider = modelProvider;
    resumedModel = model;
    resumedConfig = config;
    final error = resumeError;
    if (error != null) throw error;
    return resumeResult;
  }

  @override
  Future<String> startThread({
    required String workingDirectory,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    startedThreadDirectory = workingDirectory;
    startedModelProvider = modelProvider;
    startedModel = model;
    startedConfig = config;
    return 'new-thread';
  }

  @override
  Future<void> startTurn({
    required String threadId,
    required String prompt,
    required String workingDirectory,
  }) async {}

  @override
  Future<JsonMap> listThreadTurns({
    required String threadId,
    String? cursor,
    int limit = 50,
    String sortDirection = 'desc',
  }) async {
    turnPageCursors.add(cursor);
    return turnPage;
  }

  @override
  Future<JsonMap> listThreadItems({
    required String threadId,
    required String turnId,
    String? cursor,
    int limit = 50,
  }) async {
    itemPageTurnIds.add(turnId);
    final error = itemPageError;
    if (error != null) throw error;
    final pages = itemPages;
    if (pages != null && itemPageIndex < pages.length) {
      return pages[itemPageIndex++];
    }
    return itemPage;
  }

  @override
  Future<void> unarchiveThread({required String threadId}) async {
    unarchivedThreadId = threadId;
    unarchiveCalls++;
    await unarchiveCompleter?.future;
    archivedListResponse = <JsonMap>[];
  }
}

CodexThread _thread({
  required String id,
  String? modelProvider,
  String? model,
}) => CodexThread(
  id: id,
  preview: 'preview-$id',
  createdAt: 1,
  updatedAt: 2,
  modelProvider: modelProvider,
  model: model,
);

void main() {
  testWidgets('shows the Codex Desk shell', (tester) async {
    await tester.pumpWidget(const CodexDeskApp());

    expect(find.text('Codex Desk'), findsOneWidget);
    expect(find.text('选择一个本地项目'), findsOneWidget);
    expect(find.text('任务控制台'), findsOneWidget);
  });

  testWidgets('sends a composer message when Enter is pressed', (tester) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(find.byType(TextField), '用 Enter 发送');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      controller.entries.map((entry) => entry.detail),
      contains('用 Enter 发送'),
    );

    await tester.pumpWidget(const SizedBox());
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

  test('returns a scoped approval decision to App Server', () async {
    final writes = <JsonMap>[];
    final server = CodexAppServer(messageSink: writes.add);
    final controller = CodexController(server: server);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/commandExecution/requestApproval',
        requestId: 42,
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'command': 'dart test',
        },
      ),
    );
    await controller.respondToApproval(accepted: true);

    expect(writes, [
      {
        'id': 42,
        'result': {'decision': 'accept'},
      },
    ]);
    expect(controller.pendingApproval, isNull);
    controller.dispose();
  });

  test('automatically approves supported requests in auto approval mode', () {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
    );

    controller.setApprovalMode(ApprovalMode.autoApprove);
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/fileChange/requestApproval',
        requestId: 'approval-2',
        params: {'reason': 'Update a project file'},
      ),
    );

    expect(writes, [
      {
        'id': 'approval-2',
        'result': {'decision': 'accept'},
      },
    ]);
    expect(controller.pendingApproval, isNull);
    expect(
      controller.entries.map((entry) => entry.title),
      contains('已自动批准本次操作'),
    );
    controller.dispose();
  });

  test('coalesces agent deltas into one timeline entry', () async {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'message-1', 'delta': 'Hello'},
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'message-1', 'delta': ' world'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final agentEntries = controller.entries
        .where((entry) => entry.kind == TimelineKind.agent)
        .toList();
    expect(agentEntries, hasLength(1));
    expect(agentEntries.single.detail, 'Hello world');
    controller.dispose();
  });

  test('refuses to switch workspaces while a turn is running', () async {
    final controller = CodexController(server: CodexAppServer());
    controller
      ..workspacePath = '/original/workspace'
      ..status = RuntimeStatus.running;

    await controller.selectWorkspace('/private/tmp');

    expect(controller.workspacePath, '/original/workspace');
    expect(controller.lastError, contains('先停止当前运行时'));
    controller.dispose();
  });

  test('persists and restores the most recently selected workspace', () async {
    final store = _FakeRuntimeConfigurationStore();
    final firstController = CodexController(
      server: CodexAppServer(),
      relayProviderStore: _EmptyRelayProviderStore(),
      runtimeConfigurationStore: store,
    );

    await firstController.selectWorkspace(Directory.systemTemp.path);

    expect(store.savedWorkspace, firstController.workspacePath);
    firstController.dispose();

    final restoredController = CodexController(
      server: CodexAppServer(),
      relayProviderStore: _EmptyRelayProviderStore(),
      runtimeConfigurationStore: store,
    );
    await restoredController.waitForInitialConfiguration();

    expect(restoredController.workspacePath, store.savedWorkspace);
    restoredController.dispose();
  });

  test('updates visible account state from App Server notifications', () {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'account/updated',
        params: {'authMode': 'chatgpt', 'planType': 'plus'},
      ),
    );

    expect(controller.authStatus, AuthStatus.chatgpt);
    expect(controller.authLabel, 'ChatGPT plus');
    controller.dispose();
  });

  test(
    'builds a Responses-only relay configuration without leaking its key',
    () {
      const relay = RelayProviderConfiguration(
        baseUrl: 'https://relay.example.com/v1',
        model: 'codex-compatible-model',
        apiKey: 'relay-secret',
      );

      expect(relay.processEnvironment, {
        RelayProviderConfiguration.environmentVariable: 'relay-secret',
      });
      expect(relay.threadConfig, {
        'model_providers': {
          RelayProviderConfiguration.providerId: {
            'name': 'Codex Desk Relay',
            'base_url': 'https://relay.example.com/v1',
            'env_key': RelayProviderConfiguration.environmentVariable,
            'wire_api': 'responses',
          },
        },
      });
    },
  );

  test('only permits HTTPS relay URLs except localhost', () {
    expect(
      () => RelayProviderConfiguration.normalizeBaseUrl('http://relay.test/v1'),
      throwsFormatException,
    );
    expect(
      RelayProviderConfiguration.normalizeBaseUrl('http://localhost:8080/v1/'),
      'http://localhost:8080/v1',
    );
  });

  test(
    'permits sending with a configured relay when OpenAI auth is required',
    () {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..requiresOpenaiAuth = true
        ..authStatus = AuthStatus.signedOut;

      expect(controller.canSend, isFalse);

      controller.relayProvider = const RelayProviderConfiguration(
        baseUrl: 'https://relay.example.com/v1',
        model: 'relay-model',
        apiKey: 'relay-secret',
      );

      expect(controller.canSend, isTrue);
      controller.dispose();
    },
  );

  test('locks runtime startup before waiting for Keychain', () async {
    final store = _DelayedRelayProviderStore();
    final controller = CodexController(
      server: CodexAppServer(executable: '/not/a/codex'),
      relayProviderStore: store,
    )..workspacePath = Directory.systemTemp.path;

    final firstStart = controller.startRuntime();
    final secondStart = controller.startRuntime();

    expect(controller.status, RuntimeStatus.starting);
    store.completer.complete(null);
    await Future.wait([firstStart, secondStart]);

    expect(
      controller.entries.where((entry) => entry.title == '正在启动本地运行时'),
      hasLength(1),
    );
    controller.dispose();
  });

  test('reports a clear diagnostic for a missing Codex executable', () async {
    final server = CodexAppServer(executable: '/not/a/codex');

    final probe = await server.probe();

    expect(probe.isAvailable, isFalse);
    expect(probe.error, contains('未找到 Codex CLI'));
    await server.dispose();
  });

  test('preserves the historical provider when resuming a thread', () async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..relayProvider = const RelayProviderConfiguration(
        baseUrl: 'https://relay.example.com/v1',
        model: 'relay-model',
        apiKey: 'secret',
      );

    await controller.resumeThread(
      _thread(id: 'openai-thread', modelProvider: 'openai', model: 'gpt-5'),
    );

    expect(server.resumedThreadId, 'openai-thread');
    expect(server.resumedModelProvider, 'openai');
    expect(server.resumedModel, 'gpt-5');
    expect(server.resumedConfig, isNull);
    controller.dispose();
  });

  test(
    'passes the selected reasoning effort to new and resumed threads',
    () async {
      final store = _FakeRuntimeConfigurationStore();
      final server = _FakeCodexAppServer();
      final controller = CodexController(
        server: server,
        relayProviderStore: _EmptyRelayProviderStore(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..relayProvider = const RelayProviderConfiguration(
          baseUrl: 'https://relay.example.com/v1',
          model: 'relay-model',
          apiKey: 'secret',
        );

      await controller.setReasoningEffort(ReasoningEffort.high);
      await controller.sendPrompt('开始新任务');

      expect(store.savedReasoningEffort, 'high');
      expect(
        server.startedModelProvider,
        RelayProviderConfiguration.providerId,
      );
      expect(server.startedConfig, {
        'model_providers': {
          RelayProviderConfiguration.providerId: {
            'name': 'Codex Desk Relay',
            'base_url': 'https://relay.example.com/v1',
            'env_key': RelayProviderConfiguration.environmentVariable,
            'wire_api': 'responses',
          },
        },
        'model_reasoning_effort': 'high',
      });

      controller
        ..activeThreadId = null
        ..status = RuntimeStatus.ready;
      await controller.resumeThread(
        _thread(id: 'openai-thread', model: 'gpt-5'),
      );

      expect(server.resumedConfig, {'model_reasoning_effort': 'high'});
      controller.dispose();
    },
  );

  test(
    'loads user, agent, and command history when resuming a thread',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'turn-1',
                'items': [
                  {
                    'id': 'user-item',
                    'type': 'userMessage',
                    'content': [
                      {'type': 'text', 'text': '历史问题'},
                    ],
                  },
                  {'id': 'agent-item', 'type': 'agentMessage', 'text': '历史回答'},
                  {
                    'id': 'command-item',
                    'type': 'commandExecution',
                    'command': 'dart test',
                    'aggregatedOutput': 'All tests passed',
                  },
                  {
                    'id': 'search-item',
                    'type': 'webSearch',
                    'query': 'Codex App Server',
                    'results': [{}, {}],
                  },
                  {
                    'id': 'mcp-item',
                    'type': 'mcpToolCall',
                    'server': 'docs',
                    'tool': 'search',
                    'status': 'completed',
                  },
                ],
              },
            ],
          },
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'history-thread'));

      expect(
        controller.entries.map((entry) => '${entry.title}:${entry.detail}'),
        containsAll([
          '你:历史问题',
          'Codex:历史回答',
          '执行命令:dart test\nAll tests passed',
          '网页搜索:Codex App Server · 2 条结果',
          'MCP 工具：docs/search:completed',
        ]),
      );
      controller.dispose();
    },
  );

  test('restores the previous active thread when resume fails', () async {
    final server = _FakeCodexAppServer()..resumeError = StateError('offline');
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'old-thread';

    await controller.resumeThread(_thread(id: 'new-thread'));

    expect(controller.status, RuntimeStatus.ready);
    expect(controller.activeThreadId, 'old-thread');
    expect(controller.lastError, 'offline');
    controller.dispose();
  });

  test(
    'hydrates older turns when resume returns a pagination cursor',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'turnsBackwardsCursor': 'older-cursor',
          'thread': {
            'turns': [
              {
                'id': 'new-turn',
                'startedAt': 2,
                'items': [
                  {'id': 'new-agent', 'type': 'agentMessage', 'text': '新回答'},
                ],
              },
            ],
          },
        }
        ..turnPage = {
          'data': [
            {
              'id': 'old-turn',
              'startedAt': 1,
              'items': [
                {
                  'id': 'old-user',
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': '旧问题'},
                  ],
                },
              ],
            },
          ],
          'nextCursor': null,
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'paginated-thread'));

      expect(server.turnPageCursors, ['older-cursor']);
      final details = controller.entries.map((entry) => entry.detail).toList();
      expect(details.indexOf('旧问题'), lessThan(details.indexOf('新回答')));
      controller.dispose();
    },
  );

  test(
    'hydrates unloaded turn items through thread items pagination',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'summary-turn',
                'itemsView': 'notLoaded',
                'items': <JsonMap>[],
              },
            ],
          },
        }
        ..itemPage = {
          'data': [
            {
              'turnId': 'summary-turn',
              'item': {
                'id': 'hydrated-agent',
                'type': 'agentMessage',
                'text': '按项分页恢复的回答',
              },
            },
          ],
          'nextCursor': null,
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'item-history-thread'));

      expect(server.itemPageTurnIds, ['summary-turn']);
      expect(
        controller.entries.map((entry) => entry.detail),
        contains('按项分页恢复的回答'),
      );
      controller.dispose();
    },
  );

  test('keeps the prior timeline when item history hydration fails', () async {
    final server = _FakeCodexAppServer()
      ..resumeResult = {
        'thread': {
          'turns': [
            {
              'id': 'unavailable-turn',
              'itemsView': 'notLoaded',
              'items': <JsonMap>[],
            },
          ],
        },
      }
      ..itemPageError = StateError('items unavailable');
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'old-thread';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'old-message', 'delta': '旧线程回答'},
      ),
    );

    await controller.resumeThread(_thread(id: 'target-thread'));

    expect(controller.activeThreadId, 'old-thread');
    expect(controller.entries.map((entry) => entry.detail), contains('旧线程回答'));
    controller.dispose();
  });

  test(
    'keeps partial item history when a turn exceeds the page limit',
    () async {
      final pages = List<JsonMap>.generate(
        20,
        (index) => {
          'data': [
            {
              'turnId': 'long-turn',
              'item': {
                'id': 'item-$index',
                'type': 'agentMessage',
                'text': '第 $index 项',
              },
            },
          ],
          'nextCursor': 'cursor-$index',
        },
      );
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'long-turn',
                'itemsView': 'notLoaded',
                'items': <JsonMap>[],
              },
            ],
          },
        }
        ..itemPages = pages;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'long-history-thread'));

      expect(controller.activeThreadId, 'long-history-thread');
      expect(server.itemPageTurnIds, hasLength(20));
      expect(
        controller.entries.map((entry) => entry.title),
        contains('历史内容未完全加载'),
      );
      controller.dispose();
    },
  );

  test('ignores an older concurrent thread refresh result', () async {
    final server = _FakeCodexAppServer()..queueListRequests = true;
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace';

    final first = controller.refreshThreads();
    final second = controller.refreshThreads();
    expect(server.listRequests, hasLength(2));

    server.listRequests[1].complete([
      {'id': 'newer', 'preview': 'newer'},
    ]);
    await second;
    server.listRequests[0].complete([
      {'id': 'older', 'preview': 'older'},
    ]);
    await first;

    expect(controller.threads.single.id, 'newer');
    expect(controller.threadsLoading, isFalse);
    controller.dispose();
  });

  test('restores archived threads to the active thread list', () async {
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'restored-thread', 'preview': '已恢复任务'},
      ]
      ..archivedListResponse = [
        {'id': 'restored-thread', 'preview': '已恢复任务'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.refreshArchivedThreads();
    expect(controller.archivedThreads.single.id, 'restored-thread');

    await controller.unarchiveThread(controller.archivedThreads.single);

    expect(server.unarchivedThreadId, 'restored-thread');
    expect(controller.archivedThreads, isEmpty);
    expect(controller.threads.single.id, 'restored-thread');
    controller.dispose();
  });

  test('prevents duplicate archived thread restore requests', () async {
    final server = _FakeCodexAppServer()
      ..archivedListResponse = [
        {'id': 'restore-once', 'preview': '只恢复一次'},
      ]
      ..unarchiveCompleter = Completer<void>();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.refreshArchivedThreads();
    final thread = controller.archivedThreads.single;
    final first = controller.unarchiveThread(thread);
    await Future<void>.delayed(Duration.zero);
    await controller.unarchiveThread(thread);

    expect(server.unarchiveCalls, 1);
    expect(controller.isUnarchivingThread(thread.id), isTrue);
    server.unarchiveCompleter!.complete();
    await first;
    expect(controller.isUnarchivingThread(thread.id), isFalse);
    controller.dispose();
  });

  test('refreshes archived threads after archive notifications', () async {
    final server = _FakeCodexAppServer()
      ..archivedListResponse = [
        {'id': 'archived-now', 'preview': '已归档'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.refreshArchivedThreads();
    server.archivedListResponse = <JsonMap>[];
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/archived',
        params: {'threadId': 'archived-now'},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.archivedThreads, isEmpty);
    controller.dispose();
  });
}
