import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  test('restores the previous active thread when resume fails', () async {
    final server = FakeCodexAppServer()..resumeError = StateError('offline');
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'old-thread';

    await controller.resumeThread(threadForTest(id: 'new-thread'));

    expect(controller.status, RuntimeStatus.ready);
    expect(controller.activeThreadId, 'old-thread');
    expect(server.resumedThreadId, 'new-thread');
    expect(controller.lastError, 'offline');
    controller.dispose();
  });

  test(
    'keeps the previous timeline clean when a resume writer conflict occurs',
    () async {
      final server = FakeCodexAppServer()
        ..resumeError = StateError('thread already has an active writer');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..activeThreadId = 'old-thread';
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: '仍在查看旧任务',
          createdAt: DateTime(2026),
        ),
      ]);

      await controller.resumeThread(threadForTest(id: 'shared-thread'));

      expect(controller.activeThreadId, 'old-thread');
      expect(controller.hasResumeConflict, isTrue);
      expect(
        controller.entries.where((entry) => entry.title == '无法恢复任务'),
        isEmpty,
      );
      expect(controller.entries.single.detail, '仍在查看旧任务');
      controller.dispose();
    },
  );

  testWidgets(
    'shows a non-blocking retry notice when another app owns a thread writer',
    (tester) async {
      final server = FakeCodexAppServer()
        ..resumeError = StateError('thread already has an active writer');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(threadForTest(id: 'shared-thread'));
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(
        find.byKey(const Key('thread-open-elsewhere-notice')),
        findsOneWidget,
      );
      expect(find.text('已在另一个应用中打开'), findsOneWidget);
      expect(find.text('请先在那边关闭会话，然后重试此操作。'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      server.resumeError = null;
      await tester.tap(find.byKey(const Key('thread-open-elsewhere-retry')));
      await tester.pump();
      await tester.pump();

      expect(controller.activeThreadId, 'shared-thread');
      expect(controller.hasResumeConflict, isFalse);
      expect(
        find.byKey(const Key('thread-open-elsewhere-notice')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'keeps the writer-conflict retry when runtime is temporarily unavailable',
    () async {
      final server = ManagedRuntimeFakeServer()
        ..running = true
        ..resumeError = StateError('thread already has an active writer');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(threadForTest(id: 'shared-thread'));
      expect(controller.hasResumeConflict, isTrue);

      server.running = false;
      await controller.retryThreadWriterConflict();

      expect(controller.hasResumeConflict, isTrue);
      expect(controller.isRetryingThreadWriterConflict, isFalse);
      expect(controller.threadWriterConflictFeedback, '运行时尚未连接，请稍后重试。');
      controller.dispose();
    },
  );

  testWidgets('requires unarchive before reopening a task archived elsewhere', (
    tester,
  ) async {
    final server = FakeCodexAppServer()
      ..resumeError = StateError('session archived-thread is archived')
      ..archivedListResponse = [
        {'id': 'archived-thread', 'preview': '已归档任务'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.resumeThread(threadForTest(id: 'archived-thread'));
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(controller.activeThreadId, isNull);
    expect(
      controller.entries.where((entry) => entry.title == '无法恢复任务'),
      isEmpty,
    );
    expect(find.byKey(const Key('thread-archived-notice')), findsOneWidget);
    expect(find.text('取消归档'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  test(
    'keeps the archived-task restore action after unarchive fails',
    () async {
      final server = FakeCodexAppServer()
        ..resumeError = StateError('session archived-thread is archived')
        ..unarchiveError = StateError('unarchive unavailable');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(threadForTest(id: 'archived-thread'));
      await controller.restoreArchivedThread();

      expect(controller.hasArchivedThreadRestore, isTrue);
      expect(controller.lastError, 'unarchive unavailable');
      controller.dispose();
    },
  );

  test('clears a writer-conflict retry when switching workspaces', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-writer-conflict-switch-',
    );
    addTearDown(() => root.delete(recursive: true));
    final first = await Directory('${root.path}/first').create();
    final second = await Directory('${root.path}/second').create();
    final server = ManagedRuntimeFakeServer()
      ..resumeError = StateError('thread already has an active writer')
      ..running = true;
    final controller =
        CodexController(
            server: server,
            runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
            conversationHistoryStore: MemoryConversationHistoryStore(),
          )
          ..workspacePath = first.path
          ..status = RuntimeStatus.ready;

    await controller.resumeThread(threadForTest(id: 'shared-thread'));
    expect(controller.hasThreadWriterConflict, isTrue);

    expect(await controller.selectWorkspaceAndReconnect(second.path), isTrue);
    expect(controller.workspacePath, await second.resolveSymbolicLinks());
    expect(controller.hasThreadWriterConflict, isFalse);
    await controller.retryThreadWriterConflict();
    expect(server.resumeCalls, 1);
    controller.dispose();
  });

  test(
    'clears a writer-conflict retry when creating a new conversation',
    () async {
      final server = ManagedRuntimeFakeServer()
        ..resumeError = StateError('thread already has an active writer')
        ..running = true;
      final controller =
          CodexController(
              server: server,
              runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
              conversationHistoryStore: MemoryConversationHistoryStore(),
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;

      await controller.resumeThread(threadForTest(id: 'shared-thread'));
      expect(controller.hasThreadWriterConflict, isTrue);

      controller.createThread();

      expect(controller.activeThreadId, isNull);
      expect(controller.hasThreadWriterConflict, isFalse);
      expect(controller.threadWriterConflictFeedback, isNull);
      controller.dispose();
    },
  );

  test(
    'archives selected tasks in sequence and clears their local pins',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'first', 'preview': 'first'},
          {'id': 'second', 'preview': 'second'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();
      controller.toggleThreadPinned(controller.threads.first);

      await controller.archiveThreads(controller.threads);

      expect(server.archivedThreadIds, ['first', 'second']);
      expect(controller.threads, isEmpty);
      expect(controller.isThreadPinned('first'), isFalse);
      expect(
        controller.entries
            .lastWhere((entry) => entry.title == '任务已批量归档')
            .detail,
        '已归档 2 个任务。',
      );
      controller.dispose();
    },
  );

  test(
    'archives idle tasks while another task is running and skips the running task',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'running', 'preview': 'running', 'status': 'active'},
          {'id': 'idle', 'preview': 'idle', 'status': 'idle'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'running';
      await controller.refreshThreads();

      final result = await controller.archiveThreads(controller.threads);

      expect(result.archivedIds, {'idle'});
      expect(result.runningThreadIds, {'running'});
      expect(server.archivedThreadIds, ['idle']);
      expect(controller.threads.map((thread) => thread.id), ['running']);
      controller.dispose();
    },
  );

  test('does not send an archive request for a running target task', () async {
    final server = FakeCodexAppServer()
      ..listResponse = [
        {'id': 'running', 'preview': 'running', 'status': 'inProgress'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await controller.refreshThreads();

    final result = await controller.archiveThreads(controller.threads);

    expect(result.archivedIds, isEmpty);
    expect(result.runningThreadIds, {'running'});
    expect(server.archiveCalls, 0);
    expect(controller.threads.single.id, 'running');
    controller.dispose();
  });

  test(
    'reports idle tasks that cannot archive while runtime is unavailable',
    () async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.stopped
        ..threads = [threadForTest(id: 'offline', status: 'idle')];

      final result = await controller.archiveThreads(controller.threads);

      expect(result.archivedIds, isEmpty);
      expect(result.unavailableThreadIds, {'offline'});
      controller.dispose();
    },
  );

  testWidgets('shows archive progress until the server confirms the request', (
    tester,
  ) async {
    final server = FakeCodexAppServer()
      ..listResponse = [
        {'id': 'archive-me', 'preview': 'archive-me', 'status': 'idle'},
      ]
      ..archiveCompleter = Completer<void>();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await controller.refreshThreads();
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final taskTile = find.byKey(
      const ValueKey('sidebar-thread-tile-archive-me'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(taskTile));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sidebar-thread-archive-archive-me')),
    );
    await tester.pump();
    await tester.pump();

    expect(server.archiveCalls, 1);
    expect(
      find.byKey(const Key('sidebar-updating-task-indicator')),
      findsOneWidget,
    );
    expect(taskTile, findsOneWidget);

    server.archiveCompleter!.complete();
    await tester.pumpAndSettle();

    expect(taskTile, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'blocks sending on the active thread while its archive request is pending',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'archive-me', 'preview': 'archive-me', 'status': 'idle'},
        ]
        ..archiveCompleter = Completer<void>();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();
      final thread = controller.threads.single;
      await controller.resumeThread(thread);
      expect(controller.canSend, isTrue);

      final archive = controller.archiveThread(thread);
      await Future<void>.delayed(Duration.zero);

      expect(controller.canSend, isFalse);
      expect(await controller.sendPrompt('must not start'), isFalse);
      expect(server.startedTurnPrompts, isEmpty);

      server.archiveCompleter!.complete();
      expect((await archive).archivedIds, {thread.id});
      controller.dispose();
    },
  );

  test(
    'rechecks each task status while a batch archive is in progress',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'first', 'preview': 'first', 'status': 'idle'},
          {'id': 'second', 'preview': 'second', 'status': 'idle'},
        ]
        ..archiveCompleter = Completer<void>();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();
      final selected = List<CodexThread>.of(controller.threads);

      final archive = controller.archiveThreads(selected);
      await Future<void>.delayed(Duration.zero);
      expect(server.archiveCalls, 1);

      controller.threads = [
        controller.threads.first,
        controller.threads.last.copyWith(status: 'active'),
      ];
      server.archiveCompleter!.complete();
      final result = await archive;

      expect(server.archiveCalls, 1);
      expect(server.archivedThreadIds, ['first']);
      expect(result.archivedIds, {'first'});
      expect(result.runningThreadIds, {'second'});
      expect(controller.threads.single.id, 'second');
      controller.dispose();
    },
  );

  testWidgets(
    'enters batch archive from the project menu and archives selected tasks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'running', 'preview': 'running', 'status': 'active'},
          {'id': 'idle', 'preview': 'idle', 'status': 'idle'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final workspaceTile = find.byKey(
        const ValueKey('sidebar-workspace-/workspace'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.moveTo(tester.getCenter(workspaceTile));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('sidebar-workspace-more-/workspace')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('归档聊天'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('已选 0 个任务'), findsOneWidget);

      final runningTile = find.byKey(
        const ValueKey('sidebar-thread-tile-running'),
      );
      final idleTile = find.byKey(const ValueKey('sidebar-thread-tile-idle'));
      final sidebarTaskList = find.byKey(const Key('sidebar-task-list'));
      expect(tester.getSize(runningTile).height, 56);
      await tester.dragUntilVisible(
        runningTile,
        sidebarTaskList,
        const Offset(0, -160),
      );
      await tester.tap(
        find.descendant(of: runningTile, matching: find.byType(Checkbox)),
      );
      await tester.dragUntilVisible(
        idleTile,
        sidebarTaskList,
        const Offset(0, -160),
      );
      await tester.tap(
        find.descendant(of: idleTile, matching: find.byType(Checkbox)),
      );
      await tester.pump();
      expect(find.text('已选 2 个任务'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '归档已选'));
      await tester.pump();

      expect(server.archivedThreadIds, ['idle']);
      expect(controller.threads.map((thread) => thread.id), ['running']);
      expect(find.text('已归档 1 个任务；跳过 1 个运行中的任务。'), findsOneWidget);
      expect(find.text('已选 1 个任务'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('explains why a running task cannot be archived', (tester) async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running'
      ..threads = [threadForTest(id: 'running', status: 'active')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byTooltip('任务进行中；停止后才能归档'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar-thread-archive-running')),
      findsNothing,
    );
    expect(server.archiveCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'keeps an archived task hidden when an older active refresh completes',
    () async {
      final server = FakeCodexAppServer()..queueListRequests = true;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..threads = [threadForTest(id: 'archive-me')];

      final staleRefresh = controller.refreshThreads();
      expect(server.listRequests, hasLength(1));

      await controller.archiveThread(controller.threads.single);
      expect(controller.threads, isEmpty);

      server.listRequests.single.complete([
        {'id': 'archive-me', 'preview': 'stale active task'},
      ]);
      await staleRefresh;

      expect(controller.threads, isEmpty);
      expect(controller.threadsLoading, isFalse);
      controller.dispose();
    },
  );

  test(
    'does not restore an archived task from local session fallback',
    () async {
      final localSessions = MemoryLocalSessionThreadStore()
        ..threadsByWorkspace['/workspace'] = [threadForTest(id: 'archive-me')];
      final server = FakeCodexAppServer();
      final controller =
          CodexController(
              server: server,
              localSessionThreadStore: localSessions,
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready
            ..threads = [threadForTest(id: 'archive-me')];

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'thread/archived',
          params: {'threadId': 'archive-me'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.threads, isEmpty);
      controller.dispose();
    },
  );

  testWidgets(
    'blocks archive with the writer-conflict notice and retries the archive',
    (tester) async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'shared-thread', 'preview': 'shared'},
        ]
        ..archiveError = StateError('thread already has an active writer');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();

      await controller.archiveThread(controller.threads.single);
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(controller.hasThreadWriterConflict, isTrue);
      expect(controller.threads.single.id, 'shared-thread');
      expect(
        find.byKey(const Key('thread-open-elsewhere-notice')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        controller.entries.where((entry) => entry.title == '归档失败'),
        isEmpty,
      );

      server.archiveError = null;
      await tester.tap(find.byKey(const Key('thread-open-elsewhere-retry')));
      await tester.pump();
      await tester.pump();

      expect(server.archivedThreadIds, ['shared-thread']);
      expect(controller.hasThreadWriterConflict, isFalse);
      expect(
        find.byKey(const Key('thread-open-elsewhere-notice')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'retries every unarchived task after a batch archive writer conflict',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'first', 'preview': 'first'},
          {'id': 'second', 'preview': 'second'},
          {'id': 'third', 'preview': 'third'},
        ]
        ..archiveErrorsById['second'] = StateError(
          'thread already has an active writer',
        );
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();

      final firstPass = await controller.archiveThreads(controller.threads);

      expect(firstPass.archivedIds, {'first'});
      expect(server.archivedThreadIds, ['first']);
      expect(controller.threads.map((thread) => thread.id), [
        'second',
        'third',
      ]);
      expect(controller.hasThreadWriterConflict, isTrue);

      server.archiveErrorsById.remove('second');
      await controller.retryThreadWriterConflict();

      expect(server.archivedThreadIds, ['first', 'second', 'third']);
      expect(controller.threads, isEmpty);
      expect(server.archiveCalls, 4);
      expect(controller.hasThreadWriterConflict, isFalse);
      controller.dispose();
    },
  );

  test(
    'prevents duplicate archive requests for a task already updating',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'archive-once', 'preview': '只归档一次'},
        ]
        ..archiveCompleter = Completer<void>();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();
      final thread = controller.threads.single;

      final first = controller.archiveThreads([thread]);
      await Future<void>.delayed(Duration.zero);
      final second = await controller.archiveThreads([thread]);

      expect(server.archiveCalls, 1);
      expect(second.archivedIds, isEmpty);
      expect(second.updatingThreadIds, {thread.id});
      server.archiveCompleter!.complete();
      expect((await first).archivedIds, {thread.id});
      controller.dispose();
    },
  );

  test(
    'permanently deletes an archived task and removes it from local lists',
    () async {
      final server = FakeCodexAppServer()
        ..archivedListResponse = [
          {'id': 'remove-me', 'preview': 'remove-me'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshArchivedThreads();

      await controller.deleteThread(controller.archivedThreads.single);

      expect(server.deletedThreadIds, ['remove-me']);
      expect(controller.archivedThreads, isEmpty);
      expect(
        controller.entries
            .lastWhere((entry) => entry.title == '任务已永久删除')
            .detail,
        'remove-me',
      );
      controller.dispose();
    },
  );

  test('does not restore a deleted task from local session fallback', () async {
    final localSessions = MemoryLocalSessionThreadStore()
      ..threadsByWorkspace['/workspace'] = [threadForTest(id: 'remove-me')];
    final server = FakeCodexAppServer()
      ..listResponse = [
        {'id': 'remove-me', 'preview': 'remove-me'},
      ];
    final controller =
        CodexController(server: server, localSessionThreadStore: localSessions)
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await controller.refreshThreads();

    await controller.deleteThread(controller.threads.single);

    expect(controller.threads, isEmpty);
    controller.dispose();
  });

  test(
    'persists completed batch archive state when a later task fails',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'first', 'preview': 'first'},
          {'id': 'second', 'preview': 'second'},
        ]
        ..archiveFailureIds.add('second');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();

      final result = await controller.archiveThreads(controller.threads);

      expect(result.archivedIds, {'first'});
      expect(controller.threads.single.id, 'second');
      expect(
        controller.entries
            .lastWhere((entry) => entry.title == '部分任务归档失败')
            .detail,
        contains('无法归档 second'),
      );
      controller.dispose();
    },
  );

  test('prevents duplicate archived thread restore requests', () async {
    final server = FakeCodexAppServer()
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
}
