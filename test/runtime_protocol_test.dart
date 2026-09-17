import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

CodexThread protocolThread({
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

ServerEvent tokenUsageEvent({
  required String threadId,
  required String turnId,
  required int usedTokens,
  required int totalTokens,
  Object? maximumTokens = 100000,
}) => ServerEvent(
  method: 'thread/tokenUsage/updated',
  params: {
    'threadId': threadId,
    'turnId': turnId,
    'tokenUsage': {
      'last': {'totalTokens': usedTokens},
      'total': {'totalTokens': totalTokens},
      'modelContextWindow': maximumTokens,
    },
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps authoritative context usage scoped to its thread and turn', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..activeThreadId = 'thread-a'
      ..activeTurnId = 'turn-a2';

    controller.handleServerEventForTesting(
      tokenUsageEvent(
        threadId: 'thread-a',
        turnId: 'turn-a1',
        usedTokens: 90000,
        totalTokens: 120000,
      ),
    );
    expect(controller.activeThreadTokenUsage, isNull);

    controller.handleServerEventForTesting(
      tokenUsageEvent(
        threadId: 'thread-a',
        turnId: 'turn-a2',
        usedTokens: 24000,
        totalTokens: 64000,
      ),
    );
    expect(controller.activeThreadTokenUsage?.usedTokens, 24000);
    expect(controller.activeThreadTokenUsage?.totalTokens, 64000);
    expect(controller.activeThreadTokenUsage?.maximumTokens, 100000);

    controller.handleServerEventForTesting(
      tokenUsageEvent(
        threadId: 'thread-b',
        turnId: 'turn-b1',
        usedTokens: 12000,
        totalTokens: 12000,
      ),
    );
    expect(controller.activeThreadTokenUsage?.usedTokens, 24000);

    controller
      ..activeThreadId = 'thread-b'
      ..activeTurnId = 'turn-b1';
    expect(controller.activeThreadTokenUsage?.usedTokens, 12000);

    controller
      ..activeThreadId = 'thread-a'
      ..activeTurnId = 'turn-a2';
    expect(controller.activeThreadTokenUsage?.usedTokens, 24000);
    controller.dispose();
  });

  test('rejects invalid context windows instead of inventing a fallback', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..activeThreadId = 'thread-a'
      ..activeTurnId = 'turn-a';

    controller.handleServerEventForTesting(
      tokenUsageEvent(
        threadId: 'thread-a',
        turnId: 'turn-a',
        usedTokens: 1000,
        totalTokens: 1000,
        maximumTokens: 0,
      ),
    );

    expect(controller.activeThreadTokenUsage, isNull);
    controller.dispose();
  });

  test('preserves the historical provider when resuming a thread', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.resumeThread(
      protocolThread(
        id: 'openai-thread',
        modelProvider: 'openai',
        model: 'gpt-5',
      ),
    );

    expect(server.resumedThreadId, 'openai-thread');
    expect(server.resumedModelProvider, 'openai');
    expect(server.resumedModel, 'gpt-5');
    expect(server.resumedConfig, isNull);
    controller.dispose();
  });

  test('restores a persisted goal when reopening a thread', () async {
    final server = FakeCodexAppServer()
      ..threadGoalResponse = {
        'threadId': 'goal-thread',
        'objective': '完成跨会话目标',
        'status': 'paused',
        'tokenBudget': 2000,
        'tokensUsed': 500,
        'timeUsedSeconds': 90,
      };
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.resumeThread(protocolThread(id: 'goal-thread'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.activeThreadGoal?.objective, '完成跨会话目标');
    expect(controller.activeThreadGoal?.status, 'paused');
    expect(controller.activeThreadGoal?.progress, 0.25);
    controller.dispose();
  });

  test('uses the authoritative goal returned by a lifecycle update', () async {
    final server = FakeCodexAppServer()
      ..threadGoalResponse = {
        'threadId': 'goal-thread',
        'objective': '原目标',
        'status': 'active',
        'tokenBudget': 2000,
        'tokensUsed': 500,
        'timeUsedSeconds': 120,
      }
      ..threadGoalSetResponse = {
        'threadId': 'goal-thread',
        'objective': '更新后的目标',
        'status': 'paused',
        'tokenBudget': null,
        'tokensUsed': 750,
        'timeUsedSeconds': 180,
      };
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await controller.resumeThread(protocolThread(id: 'goal-thread'));
    await Future<void>.delayed(Duration.zero);

    expect(await controller.editActiveGoal('本地输入'), isTrue);

    expect(controller.activeThreadGoal?.objective, '更新后的目标');
    expect(controller.activeThreadGoal?.status, 'paused');
    expect(controller.activeThreadGoal?.tokenBudget, isNull);
    expect(controller.activeThreadGoal?.tokensUsed, 750);
    expect(controller.activeThreadGoal?.timeUsedSeconds, 180);
    controller.dispose();
  });

  test('sets a goal from a message with busy and error isolation', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await controller.resumeThread(protocolThread(id: 'message-goal-thread'));

    controller.lastError = '已有运行时错误';
    server.setThreadGoalError = StateError('goal write failed');
    expect(await controller.setActiveGoalFromMessage('目标消息'), isFalse);
    expect(controller.goalOperationInProgress, isFalse);
    expect(controller.goalOperationError, contains('goal write failed'));
    expect(controller.lastError, '已有运行时错误');

    server.setThreadGoalError = null;
    expect(await controller.setActiveGoalFromMessage('目标消息'), isTrue);
    expect(controller.activeThreadGoal?.objective, '目标消息');
    expect(controller.lastError, '已有运行时错误');
    controller.dispose();
  });

  test('resumes a blocked goal before sending a follow-up prompt', () async {
    final server = FakeCodexAppServer()
      ..threadGoalResponse = {
        'threadId': 'blocked-thread',
        'objective': '等待用户继续',
        'status': 'blocked',
      };
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'blocked-thread';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'blocked-thread',
          'goal': {
            'threadId': 'blocked-thread',
            'objective': '等待用户继续',
            'status': 'blocked',
          },
        },
      ),
    );
    expect(controller.activeThreadGoal?.canResume, isTrue);
    expect(await controller.resumeActiveGoal(), isTrue);
    expect(server.threadGoalStatus, 'active');
    controller.dispose();
  });

  test(
    'shows goal lifecycle feedback in the active conversation timeline',
    () async {
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..activeThreadId = 'goal-feedback-thread';

      void publish(String status) {
        controller.handleServerEventForTesting(
          ServerEvent(
            method: 'thread/goal/updated',
            params: {
              'threadId': 'goal-feedback-thread',
              'goal': {
                'threadId': 'goal-feedback-thread',
                'objective': '完成反馈展示',
                'status': status,
              },
            },
          ),
        );
      }

      publish('active');
      publish('blocked');

      expect(
        controller.entries.map((entry) => entry.detail),
        containsAll(['目标已启动，正在继续', '目标需要你的输入']),
      );
      controller.dispose();
    },
  );

  test(
    'does not silently downgrade plan mode without a resolved model',
    () async {
      final server = FakeCodexAppServer();
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      expect(await controller.sendPrompt('先制定计划', planMode: true), isFalse);

      expect(server.startedTurnPrompt, isNull);
      expect(controller.lastError, contains('读取可用模型'));
      controller.dispose();
    },
  );

  test('passes every workspace root only when creating a new thread', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-thread-roots-',
    );
    addTearDown(() => root.delete(recursive: true));
    final primary = await Directory(
      '${root.path}/primary',
    ).create(recursive: true);
    final additional = await Directory(
      '${root.path}/additional',
    ).create(recursive: true);
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    await controller.selectWorkspace(primary.path);
    await controller.addWorkspaceRoot(additional.path);
    controller.status = RuntimeStatus.ready;

    await controller.sendPrompt('读取两个目录');

    expect(server.startedThreadDirectory, await primary.resolveSymbolicLinks());
    expect(server.startedRuntimeWorkspaceRoots, [
      await primary.resolveSymbolicLinks(),
      await additional.resolveSymbolicLinks(),
    ]);

    controller
      ..status = RuntimeStatus.ready
      ..activeThreadId = null;
    await controller.resumeThread(protocolThread(id: 'historical-thread'));
    expect(server.resumedThreadId, 'historical-thread');
    controller.dispose();
  });

  test('encodes runtime workspace roots in the thread start request', () async {
    final server = ProtocolCaptureCodexAppServer();
    final threadId = await server.startThread(
      workingDirectory: '/primary',
      runtimeWorkspaceRoots: const ['/primary', '/shared'],
    );

    expect(server.requestedMethod, 'thread/start');
    expect(server.requestedParams, {
      'cwd': '/primary',
      'runtimeWorkspaceRoots': ['/primary', '/shared'],
    });
    expect(threadId, 'thread-with-roots');
  });

  test('encodes composer context in the turn start request', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.startTurn(
      threadId: 'thread-1',
      prompt: r'$documents Review this image',
      workingDirectory: '/workspace',
      additionalInput: const [
        {'type': 'localImage', 'path': '/tmp/design.png'},
        {
          'type': 'skill',
          'name': 'documents',
          'path': '/skills/documents/SKILL.md',
        },
      ],
      additionalContext: const {
        'vscode': {
          'kind': 'application',
          'value': '{"activeFile":"/workspace/lib/main.dart"}',
        },
      },
      collaborationMode: const {
        'mode': 'plan',
        'settings': {
          'model': 'gpt-test',
          'reasoning_effort': null,
          'developer_instructions': null,
        },
      },
    );

    expect(server.requestedMethod, 'turn/start');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'cwd': '/workspace',
      'input': [
        {'type': 'text', 'text': r'$documents Review this image'},
        {'type': 'localImage', 'path': '/tmp/design.png'},
        {
          'type': 'skill',
          'name': 'documents',
          'path': '/skills/documents/SKILL.md',
        },
      ],
      'additionalContext': {
        'vscode': {
          'kind': 'application',
          'value': '{"activeFile":"/workspace/lib/main.dart"}',
        },
      },
      'collaborationMode': {
        'mode': 'plan',
        'settings': {
          'model': 'gpt-test',
          'reasoning_effort': null,
          'developer_instructions': null,
        },
      },
    });
  });

  test('encodes active-turn direction adjustments', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.steerTurn(
      threadId: 'thread-1',
      expectedTurnId: 'turn-1',
      prompt: '改成灰色',
      additionalInput: const [
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ],
      additionalContext: const {
        'ide': {
          'kind': 'application',
          'value': '{"activeFile":{"path":"/workspace/lib/main.dart"}}',
        },
      },
    );

    expect(server.requestedMethod, 'turn/steer');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'expectedTurnId': 'turn-1',
      'input': [
        {'type': 'text', 'text': '改成灰色'},
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ],
      'additionalContext': {
        'ide': {
          'kind': 'application',
          'value': '{"activeFile":{"path":"/workspace/lib/main.dart"}}',
        },
      },
    });
  });

  test('encodes both thread and turn IDs when interrupting a turn', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.interruptTurn(threadId: 'thread-1', turnId: 'turn-1');

    expect(server.requestedMethod, 'turn/interrupt');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'turnId': 'turn-1',
    });
  });

  test('encodes goal lifecycle operations', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.updateThreadGoal(
      threadId: 'thread-1',
      objective: '完成迁移',
      status: 'paused',
    );
    expect(server.requestedMethod, 'thread/goal/set');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'objective': '完成迁移',
      'status': 'paused',
    });

    await server.clearThreadGoal(threadId: 'thread-1');
    expect(server.requestedMethod, 'thread/goal/clear');
    expect(server.requestedParams, {'threadId': 'thread-1'});
  });

  test('encodes durable and ephemeral thread forks', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.forkThread(threadId: 'thread-1', lastTurnId: 'turn-4');
    expect(server.requestedMethod, 'thread/fork');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'lastTurnId': 'turn-4',
    });

    await server.forkThread(
      threadId: 'thread-1',
      ephemeral: true,
      excludeTurns: true,
    );
    expect(server.requestedMethod, 'thread/fork');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'ephemeral': true,
      'excludeTurns': true,
    });
  });

  test('encodes manual thread compaction', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.compactThread(threadId: 'thread-1');

    expect(server.requestedMethod, 'thread/compact/start');
    expect(server.requestedParams, {'threadId': 'thread-1'});
  });

  test('encodes structured App Server reviews', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.startReview(
      threadId: 'thread-1',
      target: const {'type': 'baseBranch', 'branch': 'origin/main'},
    );

    expect(server.requestedMethod, 'review/start');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'delivery': 'inline',
      'target': {'type': 'baseBranch', 'branch': 'origin/main'},
    });
  });

  test('encodes feedback with explicit diagnostics consent', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.uploadFeedback(
      classification: 'bug',
      includeLogs: true,
      reason: 'The composer menu closed unexpectedly.',
      threadId: 'thread-1',
      extraLogFiles: const ['/tmp/codex.log'],
      tags: const {'surface': 'composer'},
    );

    expect(server.requestedMethod, 'feedback/upload');
    expect(server.requestedParams, {
      'classification': 'bug',
      'includeLogs': true,
      'reason': 'The composer menu closed unexpectedly.',
      'threadId': 'thread-1',
      'extraLogFiles': ['/tmp/codex.log'],
      'tags': {'surface': 'composer'},
    });
  });

  test('encodes live MCP status for the selected thread', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.listMcpServerStatuses(threadId: 'thread-1');

    expect(server.requestedMethod, 'mcpServerStatus/list');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'limit': 100,
      'detail': 'toolsAndAuthOnly',
    });
  });

  test('encodes fuzzy file search with ordered workspace roots', () async {
    final server = ProtocolCaptureCodexAppServer();

    final results = await server.fuzzyFileSearch(
      query: 'main',
      roots: const ['/primary', '/shared'],
      cancellationToken: 'composer-7',
    );

    expect(results, isEmpty);
    expect(server.requestedMethod, 'fuzzyFileSearch');
    expect(server.requestedParams, {
      'query': 'main',
      'roots': ['/primary', '/shared'],
      'cancellationToken': 'composer-7',
    });
  });

  test('rejects fuzzy file results outside the active workspace', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'codex-desk-file-search-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final workspace = await Directory(
      '${temporary.path}/workspace',
    ).create(recursive: true);
    final source = File('${workspace.path}/lib/main.dart');
    await source.parent.create(recursive: true);
    await source.writeAsString('void main() {}');
    final outside = File('${temporary.path}/secret.txt');
    await outside.writeAsString('secret');
    final canonicalWorkspace = await workspace.resolveSymbolicLinks();
    final server = FakeCodexAppServer()
      ..fuzzyFileSearchResponse = [
        {
          'file_name': 'main.dart',
          'match_type': 'file',
          'path': 'lib/main.dart',
          'root': canonicalWorkspace,
          'score': 50,
          'indices': [0, 1],
        },
        {
          'file_name': 'lib',
          'match_type': 'directory',
          'path': 'lib',
          'root': canonicalWorkspace,
          'score': 45,
        },
        {
          'file_name': 'secret.txt',
          'match_type': 'file',
          'path': outside.path,
          'root': canonicalWorkspace,
          'score': 40,
        },
        {
          'file_name': 'unknown.txt',
          'match_type': 'file',
          'path': outside.path,
          'root': '${temporary.path}/unknown',
          'score': 30,
        },
      ];
    final controller = CodexController(server: server)
      ..workspacePath = canonicalWorkspace;
    addTearDown(controller.dispose);

    final results = await controller.searchWorkspaceFiles('main');

    expect(server.fuzzyFileSearchRoots.single, [canonicalWorkspace]);
    expect(results, hasLength(2));
    expect(results.first.fileName, 'main.dart');
    expect(results.first.path, await source.resolveSymbolicLinks());
    expect(results.first.indices, [0, 1]);
    expect(results.last.fileName, 'lib');
    expect(results.last.isDirectory, isTrue);
  });

  test('keeps live MCP status scoped to the selected thread', () async {
    final server = FakeCodexAppServer()
      ..mcpServerStatusResponse = [
        {
          'name': 'filesystem',
          'authStatus': 'oAuth',
          'runtimeStatus': 'starting',
          'tools': {
            'read_file': {'name': 'read_file'},
          },
        },
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..activeThreadId = 'thread-1';

    await controller.refreshRuntimeMcpServerStatuses();

    expect(server.mcpServerStatusThreadId, 'thread-1');
    expect(controller.runtimeMcpServerStatuses.single.name, 'filesystem');
    expect(controller.runtimeMcpServerStatuses.single.toolCount, 1);
    expect(
      controller.runtimeMcpServerStatuses.single.runtimeStatus,
      'starting',
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'mcpServerStatus/updated',
        params: {
          'threadId': 'other-thread',
          'name': 'filesystem',
          'status': 'ready',
        },
      ),
    );
    expect(
      controller.runtimeMcpServerStatuses.single.runtimeStatus,
      'starting',
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'mcpServerStatus/updated',
        params: {
          'threadId': 'thread-1',
          'name': 'filesystem',
          'status': 'ready',
        },
      ),
    );
    expect(
      controller.runtimeMcpServerStatuses.single.runtimeStatus,
      'connected',
    );
    controller.dispose();
  });

  test('releases stale MCP loading after switching threads', () async {
    final pending = Completer<JsonMap>();
    final server = FakeCodexAppServer()..mcpServerStatusCompleter = pending;
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..activeThreadId = 'thread-a';

    final refresh = controller.refreshRuntimeMcpServerStatuses();
    expect(controller.runtimeMcpServerStatusesLoading, isTrue);
    controller.activeThreadId = 'thread-b';
    pending.complete({
      'data': [
        {
          'name': 'stale-server',
          'authStatus': 'unknown',
          'runtimeStatus': 'connected',
          'tools': <String, Object?>{},
        },
      ],
    });
    await refresh;

    expect(controller.runtimeMcpServerStatuses, isEmpty);
    expect(controller.runtimeMcpServerStatusesLoading, isFalse);
    controller.dispose();
  });

  test('forks the active thread and switches to the returned branch', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'source-thread'
      ..threads = [protocolThread(id: 'source-thread')];

    expect(await controller.forkActiveThread(), isTrue);

    expect(server.forkedSourceThreadId, 'source-thread');
    expect(controller.activeThreadId, 'forked-thread');
    expect(controller.threads.first.id, 'forked-thread');
    controller.dispose();
  });

  test(
    'prevents duplicate thread forks while the request is pending',
    () async {
      final completer = Completer<void>();
      final server = FakeCodexAppServer()..forkThreadCompleter = completer;
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..activeThreadId = 'source-thread'
        ..threads = [protocolThread(id: 'source-thread')];

      final firstFork = controller.forkActiveThread();
      await Future<void>.delayed(Duration.zero);

      expect(controller.canForkActiveThread, isFalse);
      expect(await controller.forkActiveThread(), isFalse);
      expect(server.forkThreadCalls, 1);

      completer.complete();
      expect(await firstFork, isTrue);
      controller.dispose();
    },
  );

  test(
    'opens side chat as an ephemeral fork without switching main thread',
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
        ..activeThreadId = 'source-thread';

      final sideChat = await controller.openSideChat();

      expect(sideChat, isNotNull);
      expect(server.forkedSourceThreadId, 'source-thread');
      expect(server.forkedEphemeral, isTrue);
      expect(server.forkedExcludeTurns, isTrue);
      expect(controller.activeThreadId, 'source-thread');
      sideChat!.dispose();
      controller.dispose();
    },
  );

  test(
    'prevents duplicate side-chat forks while creation is pending',
    () async {
      final pending = Completer<void>();
      final server = FakeCodexAppServer()..forkThreadCompleter = pending;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..activeThreadId = 'thread-1';

      final first = controller.openSideChat();
      final duplicate = await controller.openSideChat();

      expect(duplicate, isNull);
      expect(server.forkThreadCalls, 1);
      expect(controller.canOpenSideChat, isFalse);

      pending.complete();
      final session = await first;
      expect(session, isNotNull);
      expect(controller.canOpenSideChat, isTrue);
      session?.dispose();
      controller.dispose();
    },
  );

  test('discards a side-chat fork after switching tasks', () async {
    final pending = Completer<void>();
    final server = FakeCodexAppServer()..forkThreadCompleter = pending;
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..activeThreadId = 'thread-1';

    final opening = controller.openSideChat();
    controller.activeThreadId = 'thread-2';
    pending.complete();

    expect(await opening, isNull);
    expect(controller.activeThreadId, 'thread-2');
    expect(controller.canOpenSideChat, isTrue);
    controller.dispose();
  });

  test(
    'keeps side-chat turns isolated and renders attributed events',
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
        ..activeThreadId = 'source-thread';
      final sideChat = await controller.openSideChat();
      expect(sideChat, isNotNull);

      expect(await sideChat!.send('给我一个状态摘要'), isTrue);
      sideChat.handleServerEvent(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'forked-thread',
            'turn': {'id': 'side-turn'},
          },
        ),
      );
      sideChat.handleServerEvent(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'forked-thread',
            'turnId': 'side-turn',
            'itemId': 'side-answer',
            'delta': '主聊天仍未切换。',
          },
        ),
      );

      expect(controller.activeThreadId, 'source-thread');
      expect(sideChat.entries.last.detail, '主聊天仍未切换。');
      sideChat.dispose();
      controller.dispose();
    },
  );

  test('starts compaction as a real active App Server turn', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await controller.resumeThread(protocolThread(id: 'thread-1'));

    expect(await controller.compactActiveThread(), isTrue);

    expect(server.compactedThreadId, 'thread-1');
    expect(controller.status, RuntimeStatus.running);
    controller.dispose();
  });

  test('cleans up failed compaction after switching tasks', () async {
    final completer = Completer<void>();
    final server = FakeCodexAppServer()..compactThreadCompleter = completer;
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [
        protocolThread(id: 'thread-1'),
        protocolThread(id: 'thread-2'),
      ];
    await controller.resumeThread(controller.threads.first);

    final compaction = controller.compactActiveThread();
    await Future<void>.delayed(Duration.zero);
    await controller.resumeThread(protocolThread(id: 'thread-2'));
    server.compactThreadError = StateError('compaction failed');
    completer.complete();

    expect(await compaction, isFalse);
    expect(controller.activeThreadId, 'thread-2');
    expect(controller.isThreadRunning('thread-1'), isFalse);
    expect(controller.status, RuntimeStatus.ready);
    controller.dispose();
  });

  test('starts a structured review from a blank workspace chat', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    expect(
      await controller.startCodeReview(const {'type': 'uncommittedChanges'}),
      isTrue,
    );

    expect(controller.activeThreadId, 'new-thread');
    expect(server.startedReviewThreadId, 'new-thread');
    expect(server.startedReviewTarget, {'type': 'uncommittedChanges'});
    expect(controller.activeTurnId, 'review-turn');
    controller.dispose();
  });

  test('cleans up a failed review after switching tasks', () async {
    final completer = Completer<void>();
    final server = FakeCodexAppServer()..startReviewCompleter = completer;
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [
        protocolThread(id: 'thread-1'),
        protocolThread(id: 'thread-2'),
      ];
    await controller.resumeThread(controller.threads.first);

    final review = controller.startCodeReview(const {
      'type': 'uncommittedChanges',
    });
    await Future<void>.delayed(Duration.zero);
    await controller.resumeThread(protocolThread(id: 'thread-2'));
    server.startReviewError = StateError('review failed');
    completer.complete();

    expect(await review, isFalse);
    expect(controller.activeThreadId, 'thread-2');
    expect(controller.isThreadRunning('thread-1'), isFalse);
    expect(controller.status, RuntimeStatus.ready);
    controller.dispose();
  });

  test('submits feedback only with the selected log preference', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    )..activeThreadId = 'thread-1';

    expect(
      await controller.submitFeedback(
        classification: 'bug',
        includeLogs: false,
        reason: 'Composer issue',
      ),
      isTrue,
    );

    expect(server.feedbackClassification, 'bug');
    expect(server.feedbackIncludeLogs, isFalse);
    expect(server.feedbackReason, 'Composer issue');
    expect(server.feedbackThreadId, 'thread-1');
    controller.dispose();
  });

  test('opts into experimental App Server fields during initialize', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.initialize();

    expect(server.requestedMethod, 'initialize');
    expect(server.requestedParams, {
      'clientInfo': {
        'name': 'chatgpt_flutter',
        'title': 'Codex Desk',
        'version': '0.1.0',
      },
      'capabilities': {
        'experimentalApi': true,
        'mcpServerOpenaiFormElicitation': true,
      },
    });
    expect(server.notifications, ['initialized']);
  });
}
