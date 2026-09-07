import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

CodexThread refreshThread(String id) =>
    CodexThread(id: id, preview: 'preview-$id', createdAt: 1, updatedAt: 2);

Future<CodexController> refreshController(FakeCodexAppServer server) async {
  final controller = CodexController(
    server: server,
    runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
  );
  await controller.waitForInitialConfiguration();
  controller.workspacePath = '/workspace';
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ignores an older concurrent thread refresh result', () async {
    final server = FakeCodexAppServer()..queueListRequests = true;
    final controller = await refreshController(server);

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

  test('keeps task positions stable when update ordering changes', () async {
    final server = FakeCodexAppServer()
      ..listResponse = [
        {
          'id': 'first',
          'preview': 'first updated most recently',
          'createdAt': 1,
          'updatedAt': 20,
          'status': 'idle',
        },
        {
          'id': 'second',
          'preview': 'second updated earlier',
          'createdAt': 2,
          'updatedAt': 10,
          'status': 'active',
        },
        {
          'id': 'new',
          'preview': 'new task',
          'createdAt': 3,
          'updatedAt': 3,
          'status': 'idle',
        },
      ];
    final controller = await refreshController(server);
    controller.threads = [refreshThread('second'), refreshThread('first')];

    await controller.refreshThreads();

    expect(controller.threads.map((thread) => thread.id), [
      'second',
      'first',
      'new',
    ]);
    expect(controller.threads[1].preview, 'first updated most recently');
    controller.dispose();
  });

  test('restores archived threads to the active thread list', () async {
    final server = FakeCodexAppServer()
      ..listResponse = [
        {'id': 'restored-thread', 'preview': '已恢复任务'},
      ]
      ..archivedListResponse = [
        {'id': 'restored-thread', 'preview': '已恢复任务'},
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      localSessionThreadStore: MemoryLocalSessionThreadStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
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

  test('refreshes archived threads after archive notifications', () async {
    final server = FakeCodexAppServer()
      ..archivedListResponse = [
        {'id': 'archived-now', 'preview': '已归档'},
      ];
    final controller = await refreshController(server);

    await controller.refreshArchivedThreads();
    server.archivedListResponse = [];
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

  test('refreshes both task lists after deletion notifications', () async {
    final server = FakeCodexAppServer()
      ..listResponse = [
        {'id': 'deleted', 'preview': 'deleted'},
      ]
      ..archivedListResponse = [
        {'id': 'deleted-archived', 'preview': 'deleted archived'},
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      localSessionThreadStore: MemoryLocalSessionThreadStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await Future.wait([
      controller.refreshThreads(),
      controller.refreshArchivedThreads(),
    ]);
    server
      ..listResponse = []
      ..archivedListResponse = [];

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/deleted',
        params: {'threadId': 'deleted'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.threads, isEmpty);
    expect(controller.archivedThreads, isEmpty);
    controller.dispose();
  });
}
