import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

CodexThread runtimeThread({required String id, String status = 'active'}) {
  return CodexThread(
    id: id,
    preview: id,
    createdAt: 0,
    updatedAt: 0,
    status: status,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records a replayed foreground completion only once', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    const completion = ServerEvent(
      method: 'turn/completed',
      params: {
        'threadId': 'thread-1',
        'turn': {'id': 'turn-1', 'status': 'completed'},
      },
    );

    controller.handleServerEventForTesting(completion);
    controller.handleServerEventForTesting(completion);

    expect(
      controller.entries.where((entry) => entry.title == '任务完成'),
      hasLength(1),
    );
    controller.dispose();
  });

  test(
    'reconciles an ID-less foreground completion from thread status',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'thread-1', 'status': 'idle'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1';
      const completion = ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'thread-1',
          'turn': {'status': 'completed'},
        },
      );

      controller.handleServerEventForTesting(completion);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.entries.where((entry) => entry.title == '任务完成'),
        hasLength(1),
      );
      controller.dispose();
    },
  );

  test('ignores an ID-less replay after a later turn has started', () async {
    final server = FakeCodexAppServer()
      ..listResponse = [
        {'id': 'thread-1', 'status': 'active'},
      ];
    final controller =
        CodexController(
            server: server,
            runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.running
          ..activeThreadId = 'thread-1'
          ..activeTurnId = 'turn-2';

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'thread-1',
          'turn': {'status': 'completed'},
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, RuntimeStatus.running);
    expect(controller.entries.where((entry) => entry.title == '任务完成'), isEmpty);
    controller.dispose();
  });

  test('keeps the connected runtime usable after a failed turn', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {
            'status': 'failed',
            'error': {'message': 'request rejected'},
          },
        },
      ),
    );

    expect(controller.status, RuntimeStatus.ready);
    expect(controller.lastError, 'request rejected');
    expect(controller.canSend, isTrue);
    expect(controller.hasFailedTurnRetry, isFalse);
    controller.dispose();
  });

  test(
    'serializes multiple completions saved to one inactive project',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-serialized-background-completions-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      final firstPath = await first.resolveSymbolicLinks();
      final secondPath = await second.resolveSymbolicLinks();
      final history = MemoryConversationHistoryStore();
      final server = ManagedRuntimeFakeServer()
        ..startThreadResponseIds.addAll(['background-a', 'background-b'])
        ..listResponsesByDirectory[firstPath] = [
          {'id': 'background-a', 'preview': 'a', 'status': 'active'},
          {'id': 'background-b', 'preview': 'b', 'status': 'active'},
        ]
        ..listResponsesByDirectory[secondPath] = const [];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        conversationHistoryStore: history,
      );
      await controller.waitForInitialConfiguration();
      expect(await controller.createWorkspace(first.path), isTrue);
      expect(await controller.createWorkspace(second.path), isTrue);
      final firstProject = controller.workspaceConfigurations.singleWhere(
        (workspace) => workspace.primaryPath == firstPath,
      );
      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      expect(await controller.sendPrompt('后台任务 A'), isTrue);
      controller.createThread();
      expect(await controller.sendPrompt('后台任务 B'), isTrue);
      expect(await controller.selectWorkspaceAndReconnect(second.path), isTrue);

      for (final threadId in ['background-a', 'background-b']) {
        controller.handleServerEventForTesting(
          ServerEvent(
            method: 'turn/completed',
            params: {
              'threadId': threadId,
              'turn': {'threadId': threadId, 'status': 'completed'},
            },
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final snapshot = history.snapshots[firstProject.id!];
      expect(
        snapshot!.threads
            .where(
              (thread) => {'background-a', 'background-b'}.contains(thread.id),
            )
            .map((thread) => thread.status),
        everyElement('idle'),
      );
      expect(
        snapshot.acknowledgedCompletedThreadIds,
        isNot(contains(anyOf('background-a', 'background-b'))),
      );
      controller.dispose();
    },
  );

  test('reconciles an id-less completion in an inactive project', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-inactive-idless-completion-',
    );
    addTearDown(() => root.delete(recursive: true));
    final first = await Directory('${root.path}/first').create();
    final second = await Directory('${root.path}/second').create();
    final firstPath = await first.resolveSymbolicLinks();
    final secondPath = await second.resolveSymbolicLinks();
    final history = MemoryConversationHistoryStore();
    final server = ManagedRuntimeFakeServer()
      ..startThreadResponseIds.add('idless-background')
      ..listResponsesByDirectory[firstPath] = [
        {
          'id': 'idless-background',
          'preview': 'background',
          'status': 'active',
        },
      ]
      ..listResponsesByDirectory[secondPath] = const [];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      conversationHistoryStore: history,
    );
    await controller.waitForInitialConfiguration();
    expect(await controller.createWorkspace(first.path), isTrue);
    expect(await controller.createWorkspace(second.path), isTrue);
    final firstProject = controller.workspaceConfigurations.singleWhere(
      (workspace) => workspace.primaryPath == firstPath,
    );
    expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
    expect(await controller.sendPrompt('等待无 ID 完成事件'), isTrue);
    expect(await controller.selectWorkspaceAndReconnect(second.path), isTrue);
    server.listResponsesByDirectory[firstPath] = [
      {'id': 'idless-background', 'preview': 'background', 'status': 'idle'},
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
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.isThreadRunning('idless-background'), isFalse);
    final snapshot = history.snapshots[firstProject.id!];
    expect(
      snapshot!.threads
          .singleWhere((thread) => thread.id == 'idless-background')
          .status,
      'idle',
    );
    expect(
      snapshot.acknowledgedCompletedThreadIds,
      isNot(contains('idless-background')),
    );
    controller.dispose();
  });

  test(
    'uses the in-memory project snapshot when switching after completion',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-completion-switch-race-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      final firstPath = await first.resolveSymbolicLinks();
      final secondPath = await second.resolveSymbolicLinks();
      final history = MemoryConversationHistoryStore();
      final server = ManagedRuntimeFakeServer()
        ..startThreadResponseIds.add('completion-switch-thread')
        ..listResponsesByDirectory[firstPath] = [
          {
            'id': 'completion-switch-thread',
            'preview': 'running',
            'status': 'active',
          },
        ]
        ..listResponsesByDirectory[secondPath] = const [];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        conversationHistoryStore: history,
      );
      await controller.waitForInitialConfiguration();
      expect(await controller.createWorkspace(first.path), isTrue);
      expect(await controller.createWorkspace(second.path), isTrue);
      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      expect(await controller.sendPrompt('完成时切回所属项目'), isTrue);
      expect(await controller.selectWorkspaceAndReconnect(second.path), isTrue);

      server.listResponsesByDirectory[firstPath] = [
        {
          'id': 'completion-switch-thread',
          'preview': 'running',
          'status': 'idle',
        },
      ];
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'completion-switch-thread',
            'turn': {
              'threadId': 'completion-switch-thread',
              'status': 'completed',
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);

      expect(controller.workspacePath, firstPath);
      expect(controller.activeThreadId, 'completion-switch-thread');
      expect(
        controller.threads
            .singleWhere((thread) => thread.id == 'completion-switch-thread')
            .status,
        'idle',
      );
      expect(
        controller.isCompletedThreadAcknowledged('completion-switch-thread'),
        isTrue,
      );
      controller.dispose();
    },
  );

  test('marks a newly completed thread as unacknowledged', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'completed-thread'
      ..threads = [runtimeThread(id: 'completed-thread')];

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );

    expect(controller.status, RuntimeStatus.ready);
    expect(controller.threads.single.status, 'idle');
    expect(
      controller.isCompletedThreadAcknowledged('completed-thread'),
      isFalse,
    );
    controller.dispose();
  });

  test(
    'acknowledges interrupted and cancelled outcomes without a blue dot',
    () {
      for (final completionStatus in ['interrupted', 'cancelled', 'canceled']) {
        final controller = CodexController(server: FakeCodexAppServer())
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.running
          ..activeThreadId = 'stopped-thread'
          ..threads = [runtimeThread(id: 'stopped-thread')];

        controller.handleServerEventForTesting(
          ServerEvent(
            method: 'turn/completed',
            params: {
              'turn': {'status': completionStatus},
            },
          ),
        );

        expect(controller.status, RuntimeStatus.ready);
        expect(controller.threads.single.status, 'idle');
        expect(
          controller.isCompletedThreadAcknowledged('stopped-thread'),
          isTrue,
          reason: completionStatus,
        );
        controller.dispose();
      }
    },
  );

  test('marks a successful background task as newly completed', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'background-thread'
      ..threads = [runtimeThread(id: 'background-thread')];

    expect(controller.canCreateThread, isTrue);
    controller.createThread();

    expect(controller.activeThreadId, isNull);
    expect(controller.status, RuntimeStatus.ready);
    expect(controller.isThreadRunning('background-thread'), isTrue);
    expect(controller.canSend, isTrue);

    expect(await controller.sendPrompt('开始另一个任务'), isTrue);
    expect(controller.activeThreadId, 'new-thread');
    expect(controller.status, RuntimeStatus.running);
    expect(controller.isThreadRunning('background-thread'), isTrue);
    expect(controller.isThreadRunning('new-thread'), isTrue);
    controller.threads = [
      runtimeThread(id: 'background-thread'),
      runtimeThread(id: 'new-thread'),
    ];
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'background-thread',
          'turn': {'status': 'completed'},
        },
      ),
    );

    expect(controller.activeThreadId, 'new-thread');
    expect(controller.status, RuntimeStatus.running);
    expect(controller.isThreadRunning('background-thread'), isFalse);
    expect(controller.isThreadRunning('new-thread'), isTrue);
    expect(
      controller.isCompletedThreadAcknowledged('background-thread'),
      isFalse,
    );
    expect(
      controller.threads
          .firstWhere((thread) => thread.id == 'background-thread')
          .status,
      'idle',
    );
    controller.dispose();
  });

  test('does not mark a cancelled background task as newly completed', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'background-thread'
      ..threads = [runtimeThread(id: 'background-thread')];
    controller.createThread();
    controller
      ..status = RuntimeStatus.running
      ..activeThreadId = 'foreground-thread'
      ..activeTurnId = 'foreground-turn'
      ..threads = [
        runtimeThread(id: 'background-thread'),
        runtimeThread(id: 'foreground-thread'),
      ];

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'background-thread',
          'turn': {'status': 'cancelled'},
        },
      ),
    );

    expect(controller.isThreadRunning('background-thread'), isFalse);
    expect(
      controller.isCompletedThreadAcknowledged('background-thread'),
      isTrue,
    );
    expect(
      controller.threads
          .firstWhere((thread) => thread.id == 'background-thread')
          .status,
      'idle',
    );
    controller.dispose();
  });
}
