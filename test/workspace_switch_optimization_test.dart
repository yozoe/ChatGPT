import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
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
}
