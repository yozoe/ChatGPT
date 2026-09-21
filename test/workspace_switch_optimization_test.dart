import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_fakes/fake_runtime_configuration_store.dart';
import 'widget_fakes/managed_runtime_fake_server.dart';
import 'widget_fakes/memory_conversation_history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CodexThread thread(String id) =>
      CodexThread(id: id, preview: id, createdAt: 0, updatedAt: 0);

  ConversationHistorySnapshot history({
    required List<CodexThread> threads,
    required String activeThreadId,
  }) => ConversationHistorySnapshot(
    threads: threads,
    archivedThreads: const [],
    entries: const [],
    fileChanges: const [],
    activeThreadId: activeThreadId,
    ownedThreadIds: threads.map((item) => item.id).toSet(),
    historyInitialized: true,
  );

  test(
    'reuses runtime and resumes only the explicitly selected task',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-fast-workspace-switch-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      final firstPath = await first.resolveSymbolicLinks();
      final secondPath = await second.resolveSymbolicLinks();
      final firstThread = thread('first-thread');
      final previousSecondThread = thread('previous-second-thread');
      final selectedSecondThread = thread('selected-second-thread');
      final store = MemoryConversationHistoryStore();
      final server = ManagedRuntimeFakeServer()
        ..listResponsesByDirectory[firstPath] = [firstThread.toJson()]
        ..listResponsesByDirectory[secondPath] = [
          previousSecondThread.toJson(),
          selectedSecondThread.toJson(),
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        conversationHistoryStore: store,
      );
      addTearDown(controller.dispose);
      await controller.waitForInitialConfiguration();
      expect(await controller.createWorkspace(firstPath), isTrue);
      expect(await controller.createWorkspace(secondPath), isTrue);
      final firstProject = controller.workspaceConfigurations.singleWhere(
        (workspace) => workspace.primaryPath == firstPath,
      );
      final secondProject = controller.workspaceConfigurations.singleWhere(
        (workspace) => workspace.primaryPath == secondPath,
      );
      store.snapshots[firstProject.id!] = history(
        threads: [firstThread],
        activeThreadId: firstThread.id,
      );
      store.snapshots[secondProject.id!] = history(
        threads: [previousSecondThread, selectedSecondThread],
        activeThreadId: previousSecondThread.id,
      );

      expect(await controller.selectWorkspaceAndReconnect(firstPath), isTrue);
      expect(server.startCalls, 1);
      server.resumeCalls = 0;

      await controller.openWorkspaceThread(
        workspace: secondPath,
        thread: selectedSecondThread,
      );

      expect(controller.workspacePath, secondPath);
      expect(controller.activeThreadId, selectedSecondThread.id);
      expect(server.resumedThreadId, selectedSecondThread.id);
      expect(server.resumeCalls, 1);
      expect(server.startCalls, 1);
      expect(server.stopCalls, 0);
      expect(
        controller.isThreadViewCached(
          workspace: firstPath,
          threadId: firstThread.id,
        ),
        isTrue,
      );
    },
  );

  test(
    'does not wait for remote hydration when switching idle projects',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-idle-workspace-switch-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      final firstPath = await first.resolveSymbolicLinks();
      final secondPath = await second.resolveSymbolicLinks();
      final firstThread = thread('first-thread');
      final secondThread = thread('second-thread');
      final store = MemoryConversationHistoryStore();
      final server = ManagedRuntimeFakeServer()
        ..listResponsesByDirectory[firstPath] = [firstThread.toJson()]
        ..listResponsesByDirectory[secondPath] = [secondThread.toJson()];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        conversationHistoryStore: store,
      );
      addTearDown(controller.dispose);
      await controller.waitForInitialConfiguration();
      expect(await controller.createWorkspace(firstPath), isTrue);
      expect(await controller.createWorkspace(secondPath), isTrue);
      final secondProject = controller.workspaceConfigurations.singleWhere(
        (workspace) => workspace.primaryPath == secondPath,
      );
      store.snapshots[secondProject.id!] = history(
        threads: [secondThread],
        activeThreadId: secondThread.id,
      );

      expect(await controller.selectWorkspaceAndReconnect(firstPath), isTrue);
      server.listResponsesByDirectory.remove(secondPath);
      server.queueListRequests = true;

      final switched = await controller
          .selectWorkspaceAndReconnect(secondPath)
          .timeout(const Duration(seconds: 1));

      expect(switched, isTrue);
      expect(controller.workspacePath, secondPath);
      expect(controller.activeThreadId, secondThread.id);
      expect(server.resumedThreadId, secondThread.id);
      expect(server.listRequests, isNotEmpty);
    },
  );

  test('loads inactive project task lists concurrently', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-parallel-project-lists-',
    );
    addTearDown(() => root.delete(recursive: true));
    final first = await Directory('${root.path}/first').create();
    final second = await Directory('${root.path}/second').create();
    final third = await Directory('${root.path}/third').create();
    final store = MemoryConversationHistoryStore();
    final controller = CodexController(
      server: ManagedRuntimeFakeServer(),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      conversationHistoryStore: store,
    );
    addTearDown(controller.dispose);
    await controller.waitForInitialConfiguration();
    expect(await controller.createWorkspace(first.path), isTrue);
    expect(await controller.createWorkspace(second.path), isTrue);
    expect(await controller.createWorkspace(third.path), isTrue);
    await controller.selectWorkspace(first.path);
    await Future<void>.delayed(Duration.zero);

    final inactiveProjects = controller.workspaceConfigurations
        .where((workspace) => workspace.primaryPath != controller.workspacePath)
        .toList(growable: false);
    for (final project in inactiveProjects) {
      store.readGates[project.id!] = Completer<void>();
    }
    store.readRequests.clear();

    final refresh = controller.refreshInactiveWorkspaceTaskLists();
    await Future<void>.delayed(Duration.zero);

    expect(
      store.readRequests.toSet(),
      inactiveProjects.map((project) => project.id).toSet(),
    );
    for (final gate in store.readGates.values) {
      gate.complete();
    }
    await refresh;
  });

  test(
    'latest skill refresh wins across a rapid A-B-A project switch',
    () async {
      final firstSkills = Completer<List<JsonMap>>();
      final secondSkills = Completer<List<JsonMap>>();
      final latestSkills = Completer<List<JsonMap>>();
      final server = ManagedRuntimeFakeServer()
        ..running = true
        ..skillListCompleters.addAll([firstSkills, secondSkills, latestSkills]);
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      addTearDown(controller.dispose);
      await controller.waitForInitialConfiguration();
      controller.workspacePath = '/workspace-a';

      final firstRefresh = controller.refreshSkills();
      controller.workspacePath = '/workspace-b';
      final secondRefresh = controller.refreshSkills();
      controller.workspacePath = '/workspace-a';
      final latestRefresh = controller.refreshSkills();
      latestSkills.complete([
        {
          'name': 'latest-skill',
          'path': '/workspace-a/latest/SKILL.md',
          'description': 'latest',
        },
      ]);
      await latestRefresh;
      secondSkills.complete([
        {
          'name': 'second-skill',
          'path': '/workspace-b/SKILL.md',
          'description': 'second',
        },
      ]);
      await secondRefresh;
      firstSkills.complete([
        {
          'name': 'first-skill',
          'path': '/workspace-a/SKILL.md',
          'description': 'first',
        },
      ]);
      await firstRefresh;

      expect(server.skillListDirectories, [
        '/workspace-a',
        '/workspace-b',
        '/workspace-a',
      ]);
      expect(controller.skills.single.name, 'latest-skill');
      expect(controller.skillsLoading, isFalse);
    },
  );
}
