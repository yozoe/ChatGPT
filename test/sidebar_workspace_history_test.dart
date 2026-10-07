import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
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

  test('refuses the system temporary directory as a workspace', () async {
    final controller = CodexController(server: CodexAppServer());

    await controller.selectWorkspace(Directory.systemTemp.path);

    expect(controller.workspacePath, isNull);
    expect(controller.lastError, contains('系统临时目录'));
    expect(runtimeConfigurationStore.savedWorkspace, isNull);
    controller.dispose();
  });

  test('cleans a persisted system temporary directory workspace', () async {
    final temporaryPath = await Directory.systemTemp.resolveSymbolicLinks();
    final store = FakeRuntimeConfigurationStore()
      ..workspace = temporaryPath
      ..workspaces = [WorkspaceConfiguration(primaryPath: temporaryPath)];
    final controller = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );

    await controller.waitForInitialConfiguration();

    expect(controller.workspacePath, isNull);
    expect(controller.workspaceConfigurations, isEmpty);
    expect(store.clearedWorkspace, isTrue);
    expect(store.savedWorkspaces, isEmpty);
    controller.dispose();
  });

  test('persists and restores the most recently selected workspace', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'codex-desk-persisted-workspace-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final store = FakeRuntimeConfigurationStore();
    final firstController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );

    await firstController.selectWorkspace(workspace.path);

    expect(store.savedWorkspace, firstController.workspacePath);
    firstController.dispose();

    final restoredController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );
    await restoredController.waitForInitialConfiguration();

    expect(restoredController.workspacePath, store.savedWorkspace);
    restoredController.dispose();
  });

  test(
    'creates switchable workspaces with independent additional directories',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-workspace-profiles-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory(
        '${root.path}/first',
      ).create(recursive: true);
      final firstAdditional = await Directory(
        '${root.path}/first-shared',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second',
      ).create(recursive: true);
      final secondAdditional = await Directory(
        '${root.path}/second-shared',
      ).create(recursive: true);
      final store = FakeRuntimeConfigurationStore();
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();

      await controller.selectWorkspace(first.path);
      await controller.addWorkspaceRoot(firstAdditional.path);
      await controller.selectWorkspace(second.path);
      await controller.addWorkspaceRoot(secondAdditional.path);

      expect(controller.workspaceConfigurations, hasLength(2));
      expect(controller.additionalWorkspacePaths, [
        await secondAdditional.resolveSymbolicLinks(),
      ]);

      await controller.selectWorkspace(first.path);

      expect(controller.additionalWorkspacePaths, [
        await firstAdditional.resolveSymbolicLinks(),
      ]);
      expect(
        controller.workspaceConfigurations
            .map((workspace) => workspace.primaryPath)
            .toList(),
        [
          await first.resolveSymbolicLinks(),
          await second.resolveSymbolicLinks(),
        ],
      );
      expect(store.savedWorkspaces, hasLength(2));
      controller.dispose();

      final restoredController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await restoredController.waitForInitialConfiguration();

      expect(
        restoredController.workspacePath,
        await first.resolveSymbolicLinks(),
      );
      expect(restoredController.additionalWorkspacePaths, [
        await firstAdditional.resolveSymbolicLinks(),
      ]);
      await restoredController.selectWorkspace(second.path);
      expect(restoredController.additionalWorkspacePaths, [
        await secondAdditional.resolveSymbolicLinks(),
      ]);
      await restoredController.selectWorkspace(first.path);
      expect(
        restoredController.workspaceConfigurations
            .map((workspace) => workspace.primaryPath)
            .toList(),
        [
          await first.resolveSymbolicLinks(),
          await second.resolveSymbolicLinks(),
        ],
      );

      await restoredController.forgetWorkspace(
        await second.resolveSymbolicLinks(),
      );
      expect(restoredController.workspaceConfigurations, hasLength(1));
      expect(
        restoredController.workspacePath,
        await first.resolveSymbolicLinks(),
      );
      restoredController.dispose();
    },
  );

  test(
    'creates an inactive project without interrupting a running task',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-create-inactive-project-',
      );
      addTearDown(() => root.delete(recursive: true));
      final active = await Directory('${root.path}/active').create();
      final created = await Directory('${root.path}/created').create();
      final additional = await Directory('${root.path}/additional').create();
      final activePath = await active.resolveSymbolicLinks();
      final createdPath = await created.resolveSymbolicLinks();
      final additionalPath = await additional.resolveSymbolicLinks();
      final server = ManagedRuntimeFakeServer();
      final store = FakeRuntimeConfigurationStore();
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();
      expect(await controller.selectWorkspaceAndReconnect(active.path), isTrue);
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'running-thread';

      expect(
        await controller.createWorkspace(
          created.path,
          name: '后台新项目',
          additionalPaths: [additional.path],
        ),
        isTrue,
      );

      expect(controller.workspacePath, activePath);
      expect(controller.activeThreadId, 'running-thread');
      expect(controller.status, RuntimeStatus.running);
      expect(server.runtimeDirectory, activePath);
      expect(server.startCalls, 1);
      expect(server.stopCalls, 0);
      expect(controller.workspaceConfigurations, hasLength(2));
      final savedProject = controller.workspaceConfigurations.singleWhere(
        (workspace) => workspace.primaryPath == createdPath,
      );
      expect(savedProject.id, isNotNull);
      expect(savedProject.name, '后台新项目');
      expect(savedProject.additionalPaths, [additionalPath]);
      expect(
        store.savedWorkspaces!
            .singleWhere((workspace) => workspace.primaryPath == createdPath)
            .name,
        '后台新项目',
      );
      expect(controller.canCreateWorkspace, isTrue);
      expect(controller.canChangePrimaryWorkspace, isTrue);
      expect(
        await controller.selectWorkspaceAndReconnect(created.path),
        isTrue,
      );
      expect(controller.workspacePath, createdPath);
      expect(server.stopCalls, 0);
      expect(server.startCalls, 1);
      controller.dispose();
    },
  );

  test(
    'creates an inactive project without rewriting legacy additional roots',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-desk-create-project-single-save-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = RejectingAdditionalWorkspaceStore();
      final controller = CodexController(
        server: FakeCodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();

      expect(await controller.createWorkspace(directory.path), isTrue);

      final canonicalPath = await directory.resolveSymbolicLinks();
      expect(controller.workspaceConfigurations, hasLength(1));
      expect(store.savedWorkspaces?.single.primaryPath, canonicalPath);
      expect(store.additionalWorkspaceSaveCalls, 0);
      expect(controller.lastError, isNull);
      controller.dispose();
    },
  );

  test(
    'creates a directory-free project and promotes its first source folder',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-desk-unrooted-project-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FakeRuntimeConfigurationStore();
      final controller = CodexController(
        server: FakeCodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();

      expect(await controller.createWorkspace(null, name: '无目录项目'), isTrue);

      final unrooted = controller.workspaceConfigurations.single;
      final unrootedPath = unrooted.primaryPath;
      expect(unrooted.isUnrooted, isTrue);
      expect(unrooted.additionalPaths, isEmpty);
      expect(store.savedWorkspaces?.single.isUnrooted, isTrue);
      await controller.toggleWorkspacePinned(unrootedPath);

      await controller.addWorkspaceRootToWorkspace(
        unrootedPath,
        directory.path,
      );

      final promoted = controller.workspaceConfigurations.single;
      expect(promoted.isUnrooted, isFalse);
      expect(promoted.primaryPath, await directory.resolveSymbolicLinks());
      expect(promoted.name, '无目录项目');
      expect(controller.isWorkspacePinned(promoted.primaryPath), isTrue);
      expect(store.savedPinnedWorkspaces, {promoted.primaryPath});
      controller.dispose();
    },
  );

  test(
    'does not activate an unrooted project while restoring projects',
    () async {
      final unrootedPath = '${WorkspaceConfiguration.unrootedPathPrefix}saved';
      final store = FakeRuntimeConfigurationStore()
        ..workspaces = [
          WorkspaceConfiguration(
            id: 'unrooted-project',
            primaryPath: unrootedPath,
            name: '无目录项目',
          ),
        ];
      final server = ManagedRuntimeFakeServer();
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: store,
      );

      await controller.connectRestoredWorkspace();

      expect(controller.workspacePath, isNull);
      expect(controller.workspaceConfigurations.single.isUnrooted, isTrue);
      expect(store.savedWorkspace, isNull);
      expect(server.startCalls, 0);
      controller.dispose();
    },
  );

  test(
    'switches projects while a turn runs and routes its completion to the owner',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-running-cross-project-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      final firstPath = await first.resolveSymbolicLinks();
      final secondPath = await second.resolveSymbolicLinks();
      final history = MemoryConversationHistoryStore();
      final server = ManagedRuntimeFakeServer()
        ..startThreadResponseIds.add('first-thread');
      final controller = CodexController(
        server: server,
        conversationHistoryStore: history,
      );
      await controller.waitForInitialConfiguration();
      expect(await controller.createWorkspace(first.path), isTrue);
      expect(await controller.createWorkspace(second.path), isTrue);
      final firstProject = controller.workspaceConfigurations.singleWhere(
        (workspace) => workspace.primaryPath == firstPath,
      );
      final secondProject = controller.workspaceConfigurations.singleWhere(
        (workspace) => workspace.primaryPath == secondPath,
      );
      history.snapshots[secondProject.id!] = ConversationHistorySnapshot(
        threads: [threadForTest(id: 'second-thread')],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
        ownedThreadIds: const {'second-thread'},
        historyInitialized: true,
      );

      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      expect(await controller.sendPrompt('第一个项目继续执行'), isTrue);
      expect(controller.isThreadRunning('first-thread'), isTrue);

      await controller.openWorkspaceThread(
        workspace: secondPath,
        thread: threadForTest(id: 'second-thread'),
      );

      expect(controller.workspacePath, secondPath);
      expect(server.stopCalls, 0);
      expect(server.startCalls, 1);
      expect(server.runtimeDirectory, firstPath);
      expect(server.resumedThreadId, 'second-thread');
      expect(controller.isThreadRunning('first-thread'), isTrue);
      expect(
        controller.isThreadRunningInWorkspace('first-thread', firstPath),
        isTrue,
      );
      expect(
        controller.isThreadRunningInWorkspace('first-thread', secondPath),
        isFalse,
      );
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.canSend, isTrue);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'first-thread',
            'turn': {
              'id': 'first-turn',
              'threadId': 'first-thread',
              'status': 'completed',
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.workspacePath, secondPath);
      expect(controller.activeThreadId, 'second-thread');
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.isThreadRunning('first-thread'), isFalse);
      expect(
        controller.isThreadRunningInWorkspace('first-thread', firstPath),
        isFalse,
      );
      final firstSnapshot = history.snapshots[firstProject.id!];
      expect(
        firstSnapshot!.threads
            .singleWhere((thread) => thread.id == 'first-thread')
            .status,
        'idle',
      );
      expect(
        firstSnapshot.acknowledgedCompletedThreadIds,
        isNot(contains('first-thread')),
      );
      expect(
        firstSnapshot
            .userMessageEntriesByThreadId['first-thread']
            ?.single
            .detail,
        '第一个项目继续执行',
      );
      expect(await controller.sendPrompt('继续第二个项目的任务'), isTrue);
      expect(server.startedTurnThreadId, 'second-thread');
      expect(server.startedTurnDirectory, secondPath);
      expect(controller.isThreadRunning('second-thread'), isTrue);
      controller.dispose();
    },
  );

  test(
    'skips superseded project switches while a background turn runs',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-serialized-project-switch-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      final third = await Directory('${root.path}/third').create();
      final firstPath = await first.resolveSymbolicLinks();
      final secondPath = await second.resolveSymbolicLinks();
      final thirdPath = await third.resolveSymbolicLinks();
      final history = BlockingReadConversationHistoryStore();
      final runtimeStore = FakeRuntimeConfigurationStore();
      final server = ManagedRuntimeFakeServer()
        ..startThreadResponseIds.add('switch-running-thread')
        ..listResponsesByDirectory[firstPath] = [
          {
            'id': 'switch-running-thread',
            'preview': 'running',
            'status': 'active',
          },
        ]
        ..listResponsesByDirectory[secondPath] = const []
        ..listResponsesByDirectory[thirdPath] = const [];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: history,
      );
      await controller.waitForInitialConfiguration();
      expect(await controller.createWorkspace(first.path), isTrue);
      expect(await controller.createWorkspace(second.path), isTrue);
      expect(await controller.createWorkspace(third.path), isTrue);
      final secondProject = controller.workspaceConfigurations.singleWhere(
        (workspace) => workspace.primaryPath == secondPath,
      );
      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      expect(await controller.sendPrompt('保持后台执行'), isTrue);

      history.blockNextRead(secondProject.id!);
      final secondSwitch = controller.selectWorkspaceAndReconnect(second.path);
      await history.readStarted!.future;
      var thirdSwitchCompleted = false;
      final thirdSwitch = controller
          .selectWorkspaceAndReconnect(third.path)
          .then((result) {
            thirdSwitchCompleted = true;
            return result;
          });
      await Future<void>.delayed(Duration.zero);

      expect(thirdSwitchCompleted, isFalse);
      history.allowRead!.complete();
      expect(await secondSwitch, isFalse);
      expect(await thirdSwitch, isTrue);

      expect(controller.workspacePath, thirdPath);
      expect(runtimeStore.savedWorkspace, thirdPath);
      expect(controller.isThreadRunning('switch-running-thread'), isTrue);
      controller.dispose();
    },
  );

  test(
    'starts a newly created project with no inherited directory tasks',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-desk-clean-project-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final server = ManagedRuntimeFakeServer()
        ..listResponse = [
          {'id': 'older-directory-task', 'preview': '来自同一目录的旧任务'},
        ];
      final history = MemoryConversationHistoryStore();
      final controller = CodexController(
        server: server,
        conversationHistoryStore: history,
      );
      await controller.waitForInitialConfiguration();

      expect(await controller.createWorkspace(directory.path), isTrue);
      expect(controller.workspacePath, isNull);
      expect(
        await controller.selectWorkspaceAndReconnect(directory.path),
        isTrue,
      );
      await controller.refreshThreads();

      expect(controller.threads, isEmpty);
      expect(controller.workspaceProjectId, isNotNull);

      server.listResponse = [
        {'id': 'new-thread', 'preview': '这个项目的新任务'},
      ];
      controller.status = RuntimeStatus.ready;
      expect(await controller.sendPrompt('创建任务'), isTrue);
      expect(controller.threads.map((thread) => thread.id), ['new-thread']);

      controller.dispose();
    },
  );

  test(
    'rejects stale replies until turn start while recording task creation first',
    () async {
      final server = FakeCodexAppServer()
        ..queueListRequests = true
        ..startThreadCompleter = Completer<String>()
        ..startTurnCompleter = Completer<void>()
        ..startThreadResponseIds.add('startup-order-thread');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      final sending = controller.sendPrompt('创建任务');
      await Future<void>.delayed(Duration.zero);

      // Until thread/start returns an ID, an ID-less buffered event cannot be
      // attributed to the new task.
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {'itemId': 'stale-reply', 'delta': '旧任务的迟到回复'},
        ),
      );
      expect(
        controller.entries.map((entry) => entry.title),
        isNot(contains('Codex')),
      );

      server.startThreadCompleter!.complete('startup-order-thread');
      await Future<void>.delayed(Duration.zero);
      expect(server.listRequests, hasLength(1));

      // turn/start is issued without waiting for the sidebar refresh, so a
      // compatible reply can already belong to the new turn.
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {'itemId': 'startup-reply', 'delta': '提前到达的回复'},
        ),
      );
      expect(controller.entries.map((entry) => entry.title), contains('Codex'));
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'startup-order-thread',
            'turn': {'id': 'stale-turn', 'status': 'completed'},
          },
        ),
      );
      expect(controller.status, RuntimeStatus.running);
      expect(
        controller.entries.map((entry) => entry.title),
        isNot(contains('任务完成')),
      );
      server.listRequests.single.complete(const [
        {'id': 'startup-order-thread', 'preview': '创建任务'},
      ]);
      for (
        var index = 0;
        index < 10 && server.startedTurnThreadId == null;
        index++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(server.startedTurnThreadId, 'startup-order-thread');

      // Once turn/start has actually been issued, compatible ID-less events
      // are accepted and remain below the local creation boundary.
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {'itemId': 'started-reply', 'delta': '新任务回复'},
        ),
      );
      server.startTurnCompleter!.complete();

      expect(await sending, isTrue);
      final titles = controller.entries.map((entry) => entry.title).toList();
      expect(titles.indexOf('你'), lessThan(titles.indexOf('任务已创建')));
      expect(titles.indexOf('任务已创建'), lessThan(titles.indexOf('Codex')));
      controller.dispose();
    },
  );

  test(
    'switches to an inactive task workspace before resuming its task',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-open-cached-task-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      final server = ManagedRuntimeFakeServer();
      final controller = CodexController(server: server);
      await controller.waitForInitialConfiguration();

      expect(await controller.createWorkspace(first.path), isTrue);
      expect(await controller.createWorkspace(second.path), isTrue);
      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      final secondPath = await second.resolveSymbolicLinks();

      await controller.openWorkspaceThread(
        workspace: secondPath,
        thread: threadForTest(id: 'second-project-thread'),
      );

      expect(controller.workspacePath, secondPath);
      expect(server.configReadDirectory, secondPath);
      expect(server.resumedThreadId, 'second-project-thread');
      controller.dispose();
    },
  );

  testWidgets('manages primary and additional workspace directories', (
    tester,
  ) async {
    late Directory root;
    late String additionalPath;
    late String secondPath;
    late CodexController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'codex-desk-workspace-dialog-',
      );
      final primary = await Directory(
        '${root.path}/primary',
      ).create(recursive: true);
      final additional = await Directory(
        '${root.path}/additional',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second',
      ).create(recursive: true);
      additionalPath = await additional.resolveSymbolicLinks();
      secondPath = await second.resolveSymbolicLinks();
      controller = CodexController(
        server: ManagedRuntimeFakeServer(),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore()
          ..workspace = primary.path
          ..additionalWorkspaces = [additional.path]
          ..workspaces = [
            WorkspaceConfiguration(
              primaryPath: primary.path,
              additionalPaths: [additional.path],
            ),
            WorkspaceConfiguration(primaryPath: second.path),
          ],
      );
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.running;
    });
    addTearDown(() => root.delete(recursive: true));
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-manage-workspaces-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const Key('workspace-directories-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('当前或后台任务完成'), findsNothing);
    expect(find.textContaining('主目录'), findsWidgets);
    expect(find.text(additionalPath), findsOneWidget);
    expect(find.text('附加目录'), findsWidgets);
    expect(find.text('新建工作区'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('create-workspace-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(ValueKey('switch-workspace-$secondPath')),
          )
          .onPressed,
      isNotNull,
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
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('create-workspace-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(ValueKey('switch-workspace-$secondPath')),
          )
          .onPressed,
      isNotNull,
    );

    final removeAdditional = find.byTooltip('移除附加目录');
    await tester.ensureVisible(removeAdditional);
    await tester.pump();
    await tester.tap(removeAdditional);
    await tester.pump();
    expect(controller.additionalWorkspacePaths, isEmpty);
    expect(
      find.byKey(const Key('additional-workspaces-empty')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'restores cached conversation history for the selected workspace',
    () async {
      final workspaceDirectory = await Directory.systemTemp.createTemp(
        'codex-desk-cached-history-',
      );
      addTearDown(() => workspaceDirectory.delete(recursive: true));
      final runtimeStore = FakeRuntimeConfigurationStore();
      final firstController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await firstController.selectWorkspace(workspaceDirectory.path);
      firstController
        ..threads = [threadForTest(id: 'cached-thread')]
        ..activeThreadId = 'cached-thread'
        ..handleServerEventForTesting(
          const ServerEvent(
            method: 'item/completed',
            params: {
              'item': {
                'type': 'fileChange',
                'changes': [
                  {
                    'path': 'lib/main.dart',
                    'kind': 'modified',
                    'diff': '+cached',
                  },
                ],
              },
            },
          ),
        );
      await firstController.saveConversationHistoryForTesting();
      final workspace = firstController.workspacePath!;
      firstController.dispose();

      final restoredController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await restoredController.waitForInitialConfiguration();

      expect(restoredController.workspacePath, workspace);
      expect(restoredController.threads.map((thread) => thread.id), [
        'cached-thread',
      ]);
      expect(restoredController.activeThreadId, 'cached-thread');
      expect(restoredController.fileChanges.single.diff, '+cached');
      expect(
        restoredController.entries.map((entry) => entry.title),
        isNot(contains('文件变更')),
      );
      restoredController.dispose();
    },
  );

  test(
    'migrates path-keyed history when a project ID was saved before migration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-desk-history-key-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final workspace = await directory.resolveSymbolicLinks();
      const projectId = 'project-partially-migrated';
      historyStore.snapshots[workspace] = ConversationHistorySnapshot(
        threads: [threadForTest(id: 'legacy-thread')],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
      );
      final runtimeStore = FakeRuntimeConfigurationStore()
        ..workspace = workspace
        ..workspaces = [
          WorkspaceConfiguration(id: projectId, primaryPath: workspace),
        ];

      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await controller.waitForInitialConfiguration();

      expect(controller.threads.map((thread) => thread.id), ['legacy-thread']);
      expect(
        historyStore.snapshots[projectId]!.threads.map((thread) => thread.id),
        ['legacy-thread'],
      );
      controller.dispose();

      final restartedController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await restartedController.waitForInitialConfiguration();
      expect(restartedController.threads.map((thread) => thread.id), [
        'legacy-thread',
      ]);
      restartedController.dispose();
    },
  );

  test(
    'keeps a queued history save under the workspace that created its snapshot',
    () async {
      final firstDirectory = await Directory.systemTemp.createTemp(
        'codex-history-queued-first-',
      );
      final secondDirectory = await Directory.systemTemp.createTemp(
        'codex-history-queued-second-',
      );
      addTearDown(() => firstDirectory.delete(recursive: true));
      addTearDown(() => secondDirectory.delete(recursive: true));
      final firstWorkspace = await firstDirectory.resolveSymbolicLinks();
      final secondWorkspace = await secondDirectory.resolveSymbolicLinks();
      final runtimeStore = FakeRuntimeConfigurationStore()
        ..workspace = firstWorkspace
        ..workspaces = [
          WorkspaceConfiguration(
            id: 'project-first',
            primaryPath: firstWorkspace,
          ),
          WorkspaceConfiguration(
            id: 'project-second',
            primaryPath: secondWorkspace,
          ),
        ];
      final delayedHistory = BlockingConversationHistoryStore();
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: delayedHistory,
      );
      await controller.waitForInitialConfiguration();

      controller.threads = [threadForTest(id: 'first-thread')];
      final firstSave = controller.saveConversationHistoryForTesting();
      await delayedHistory.firstSaveStarted.future;

      // A workspace switch can update the visible path while an older save is
      // still draining. The queued snapshot must retain the new path's key,
      // rather than consulting the stale current project ID later.
      controller.workspacePath = secondWorkspace;
      controller.threads = [threadForTest(id: 'second-thread')];
      final secondSave = controller.saveConversationHistoryForTesting();
      delayedHistory.allowFirstSave.complete();
      await Future.wait([firstSave, secondSave]);

      expect(
        delayedHistory.snapshots['project-first']!.threads.single.id,
        'first-thread',
      );
      expect(
        delayedHistory.snapshots['project-second']!.threads.single.id,
        'second-thread',
      );
      controller.dispose();
    },
  );

  test('preserves a project ID while editing its folders and name', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-project-id-',
    );
    addTearDown(() => root.delete(recursive: true));
    final primary = await Directory('${root.path}/primary').create();
    final additional = await Directory('${root.path}/additional').create();
    final primaryPath = await primary.resolveSymbolicLinks();
    final additionalPath = await additional.resolveSymbolicLinks();
    const projectId = 'stable-project-id';
    final store = FakeRuntimeConfigurationStore()
      ..workspace = primaryPath
      ..workspaces = [
        WorkspaceConfiguration(id: projectId, primaryPath: primaryPath),
      ];
    final controller = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );
    await controller.waitForInitialConfiguration();

    await controller.renameWorkspace(primaryPath, 'Renamed project');
    expect(store.savedWorkspaces!.single.id, projectId);

    await controller.addWorkspaceRoot(additionalPath);
    expect(store.savedWorkspaces!.single.id, projectId);

    await controller.removeWorkspaceRoot(additionalPath);
    expect(store.savedWorkspaces!.single.id, projectId);
    controller.dispose();
  });

  test(
    'persists pinned task IDs with each workspace history snapshot',
    () async {
      final controller =
          CodexController(
              server: CodexAppServer(),
              conversationHistoryStore: historyStore,
            )
            ..workspacePath = '/workspace'
            ..threads = [
              threadForTest(id: 'first'),
              threadForTest(id: 'second'),
            ];

      controller.toggleThreadPinned(controller.threads.last);
      await controller.acknowledgeCompletedThread('first');
      await controller.saveConversationHistoryForTesting();

      expect(historyStore.snapshots['/workspace']!.pinnedThreadIds, {'second'});
      expect(
        historyStore.snapshots['/workspace']!.acknowledgedCompletedThreadIds,
        {'first'},
      );
      controller.dispose();
    },
  );

  test(
    'continues the restored thread after reconnecting the runtime',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'codex-restored-thread-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final canonicalWorkspace = await workspace.resolveSymbolicLinks();
      final runtimeStore = FakeRuntimeConfigurationStore()
        ..workspace = canonicalWorkspace;
      historyStore.snapshots[canonicalWorkspace] = ConversationHistorySnapshot(
        threads: [threadForTest(id: 'restored-thread')],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
        activeThreadId: 'restored-thread',
      );
      final server = ManagedRuntimeFakeServer()
        ..listResponse = [
          {'id': 'restored-thread', 'preview': 'restored'},
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );

      await controller.waitForInitialConfiguration();
      await controller.startRuntime();
      expect(server.resumedThreadId, 'restored-thread');
      expect(controller.activeThreadId, 'restored-thread');

      await controller.sendPrompt('继续上一轮');
      expect(server.startedTurnThreadId, 'restored-thread');
      expect(server.startedThreadDirectory, isNull);
      controller.dispose();
    },
  );

  test(
    'keeps a cached active thread when both runtime lists are temporarily empty',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'codex-empty-thread-list-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final canonicalWorkspace = await workspace.resolveSymbolicLinks();
      final runtimeStore = FakeRuntimeConfigurationStore()
        ..workspace = canonicalWorkspace;
      historyStore.snapshots[canonicalWorkspace] = ConversationHistorySnapshot(
        threads: [threadForTest(id: 'cached-active-thread')],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
        activeThreadId: 'cached-active-thread',
      );
      final server = ManagedRuntimeFakeServer()..listResponse = const [];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
        localSessionThreadStore: MemoryLocalSessionThreadStore(),
      );

      await controller.waitForInitialConfiguration();
      await controller.startRuntime();

      expect(server.resumedThreadId, 'cached-active-thread');
      expect(controller.canSend, isTrue);
      controller.dispose();
    },
  );

  test(
    'does not retain pinned tasks when switching to a fresh workspace',
    () async {
      final firstWorkspace = await Directory.systemTemp.createTemp(
        'codex-history-first-',
      );
      final secondWorkspace = await Directory.systemTemp.createTemp(
        'codex-history-second-',
      );
      addTearDown(() => firstWorkspace.delete(recursive: true));
      addTearDown(() => secondWorkspace.delete(recursive: true));
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        conversationHistoryStore: historyStore,
      );

      await controller.selectWorkspace(firstWorkspace.path);
      controller.threads = [threadForTest(id: 'first-thread')];
      controller.toggleThreadPinned(controller.threads.single);
      await controller.selectWorkspace(secondWorkspace.path);

      expect(controller.pinnedThreadIds, isEmpty);
      controller.dispose();
    },
  );

  test(
    'does not retain acknowledged completions when creating a fresh workspace',
    () async {
      final firstWorkspace = await Directory.systemTemp.createTemp(
        'codex-acknowledged-first-',
      );
      final secondWorkspace = await Directory.systemTemp.createTemp(
        'codex-acknowledged-second-',
      );
      addTearDown(() => firstWorkspace.delete(recursive: true));
      addTearDown(() => secondWorkspace.delete(recursive: true));
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        conversationHistoryStore: historyStore,
      );

      await controller.selectWorkspace(firstWorkspace.path);
      await controller.acknowledgeCompletedThread('completed-in-first');
      final snapshotKeysBeforeSecondWorkspace = Set<String>.of(
        historyStore.snapshots.keys,
      );
      await controller.selectWorkspace(secondWorkspace.path);

      expect(
        controller.isCompletedThreadAcknowledged('completed-in-first'),
        isFalse,
      );
      final secondWorkspaceSnapshotKey = historyStore.snapshots.keys.firstWhere(
        (key) => !snapshotKeysBeforeSecondWorkspace.contains(key),
      );
      expect(
        historyStore
            .snapshots[secondWorkspaceSnapshotKey]!
            .acknowledgedCompletedThreadIds,
        isEmpty,
      );
      controller.dispose();
    },
  );

  test(
    'clears a restored terminal task reminder when explicitly switching projects',
    () async {
      final first = await Directory.systemTemp.createTemp(
        'codex-history-reminder-first-',
      );
      final second = await Directory.systemTemp.createTemp(
        'codex-history-reminder-second-',
      );
      addTearDown(() => first.delete(recursive: true));
      addTearDown(() => second.delete(recursive: true));
      final firstPath = await first.resolveSymbolicLinks();
      final secondPath = await second.resolveSymbolicLinks();
      final runtimeStore = FakeRuntimeConfigurationStore()
        ..workspace = firstPath
        ..workspaces = [
          WorkspaceConfiguration(id: 'reminder-first', primaryPath: firstPath),
          WorkspaceConfiguration(
            id: 'reminder-second',
            primaryPath: secondPath,
          ),
        ];
      historyStore.snapshots['reminder-second'] = ConversationHistorySnapshot(
        threads: [threadForTest(id: 'completed-in-second', status: 'idle')],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
        activeThreadId: 'completed-in-second',
      );
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await controller.waitForInitialConfiguration();

      await controller.selectWorkspace(secondPath);

      expect(
        controller.isCompletedThreadAcknowledged('completed-in-second'),
        isTrue,
      );
      controller.dispose();
    },
  );

  test(
    'ignores a late completion acknowledgement from another workspace',
    () async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/current';

      await controller.acknowledgeCompletedThread(
        'late-thread',
        workspace: '/previous',
      );

      expect(controller.isCompletedThreadAcknowledged('late-thread'), isFalse);
      controller.dispose();
    },
  );

  test(
    'exports and imports portable local history without changing workspace',
    () async {
      final source =
          CodexController(
              server: CodexAppServer(),
              conversationHistoryStore: historyStore,
            )
            ..workspacePath = '/source'
            ..threads = [
              threadForTest(id: 'pinned-thread'),
              threadForTest(id: 'plain-thread'),
            ];
      source.toggleThreadPinned(source.threads.first);
      await source.acknowledgeCompletedThread('plain-thread');
      final exported = source.exportConversationHistory();

      final target = CodexController(
        server: CodexAppServer(),
        conversationHistoryStore: historyStore,
      )..workspacePath = '/target';
      await target.acknowledgeCompletedThread('pinned-thread');
      await target.importConversationHistory(exported);

      expect(target.workspacePath, '/target');
      expect(target.threads.map((thread) => thread.id), [
        'pinned-thread',
        'plain-thread',
      ]);
      expect(target.isThreadPinned('pinned-thread'), isTrue);
      expect(target.isCompletedThreadAcknowledged('plain-thread'), isTrue);
      expect(target.isCompletedThreadAcknowledged('pinned-thread'), isFalse);
      expect(jsonDecode(exported)['format'], 'codex-desk-history');
      expect(historyStore.snapshots['/target']!.pinnedThreadIds, {
        'pinned-thread',
      });
      expect(
        historyStore.snapshots['/target']!.acknowledgedCompletedThreadIds,
        {'plain-thread'},
      );
      source.dispose();
      target.dispose();
    },
  );

  test('rejects local history import while a task is running', () async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/target'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running-thread'
      ..threads = [threadForTest(id: 'running-thread', status: 'running')];
    final imported = CodexController(server: CodexAppServer())
      ..workspacePath = '/source'
      ..threads = [threadForTest(id: 'imported-thread')];

    await expectLater(
      controller.importConversationHistory(
        imported.exportConversationHistory(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('等待所有任务完成'),
        ),
      ),
    );

    expect(controller.activeThreadId, 'running-thread');
    expect(controller.threads.single.id, 'running-thread');
    controller.dispose();
    imported.dispose();
  });

  test('rolls back local history import when persistence fails', () async {
    final store = FailingConversationHistoryStore();
    final controller =
        CodexController(
            server: CodexAppServer(),
            conversationHistoryStore: store,
          )
          ..workspacePath = '/target'
          ..activeThreadId = 'original-thread'
          ..threads = [threadForTest(id: 'original-thread')];
    controller.toggleThreadPinned(controller.threads.single);
    final imported = CodexController(server: CodexAppServer())
      ..workspacePath = '/source'
      ..threads = [threadForTest(id: 'imported-thread')];

    await expectLater(
      controller.importConversationHistory(
        imported.exportConversationHistory(),
      ),
      throwsA(isA<StateError>()),
    );

    expect(controller.activeThreadId, 'original-thread');
    expect(controller.threads.single.id, 'original-thread');
    expect(controller.isThreadPinned('original-thread'), isTrue);
    expect(
      controller.entries.where((entry) => entry.title == '已导入本地历史'),
      isEmpty,
    );
    controller.dispose();
    imported.dispose();
  });
}
