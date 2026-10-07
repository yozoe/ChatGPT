import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/local_worktree_record.dart';
import 'package:chatgpt/src/domain/thread_environment_binding.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';
import 'package:chatgpt/src/services/codex_clock.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
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

  test(
    'creates a branch in the active managed worktree and records it',
    () async {
      final root = await Directory.systemTemp.createTemp('worktree-branch-');
      addTearDown(() => root.delete(recursive: true));
      final worktree = '${root.path}/task-1';
      final store = RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      );
      final record = LocalWorktreeRecord(
        worktreeId: 'task-1',
        projectId: 'project-1',
        sourceRepository: '/workspace',
        worktreePath: worktree,
        baseCommit: 'abc123',
        state: LocalWorktreeState.completed,
        createdAt: DateTime.utc(2026),
        threadId: 'thread-1',
      );
      await store.saveWorktreeRecords([record]);
      final git = FakeGitProjectService();
      final controller = CodexController(
        server: FakeCodexAppServer(),
        runtimeConfigurationStore: store,
        gitProjectService: git,
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = worktree
        ..status = RuntimeStatus.ready;

      expect(
        await controller.createAndCheckoutGitBranch(
          'feature/worktree',
          workspace: worktree,
        ),
        isTrue,
      );
      expect(git.createdBranchWorkspace, worktree);
      expect(
        (await store.readWorktreeRecords()).single.branch,
        'feature/worktree',
      );
      controller.dispose();
    },
  );

  test(
    'restores a managed worktree execution directory when resuming a thread',
    () async {
      final root = await Directory.systemTemp.createTemp('worktree-resume-');
      addTearDown(() => root.delete(recursive: true));
      final worktree = '${root.path}/task-1';
      await Directory(worktree).create(recursive: true);
      final store = RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      );
      await store.saveWorktreeRecords([
        LocalWorktreeRecord(
          worktreeId: 'task-1',
          projectId: 'project-1',
          sourceRepository: '${root.path}/source',
          worktreePath: worktree,
          baseCommit: 'abc123',
          state: LocalWorktreeState.ready,
          createdAt: DateTime.now(),
        ),
      ]);
      await store.saveThreadEnvironmentBindings([
        ThreadEnvironmentBinding(
          threadId: 'thread-1',
          kind: ThreadEnvironmentKind.managedWorktree,
          workingDirectory: worktree,
          worktreeId: 'task-1',
        ),
      ]);
      final controller = CodexController(
        server: FakeCodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '${root.path}/source'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(protocolThread(id: 'thread-1'));

      expect(
        controller.activeExecutionWorkspace,
        await Directory(worktree).resolveSymbolicLinks(),
      );
      controller.dispose();
    },
  );

  test(
    'falls back to the source workspace when a bound worktree is missing',
    () async {
      final root = await Directory.systemTemp.createTemp('worktree-missing-');
      addTearDown(() => root.delete(recursive: true));
      final store = RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      );
      await store.saveThreadEnvironmentBindings([
        ThreadEnvironmentBinding(
          threadId: 'thread-1',
          kind: ThreadEnvironmentKind.managedWorktree,
          workingDirectory: '${root.path}/missing',
          worktreeId: 'missing',
        ),
      ]);
      final controller =
          CodexController(
              server: FakeCodexAppServer(),
              runtimeConfigurationStore: store,
            )
            ..workspacePath = '${root.path}/source'
            ..status = RuntimeStatus.ready;

      await controller.resumeThread(protocolThread(id: 'thread-1'));

      expect(controller.activeExecutionWorkspace, '${root.path}/source');
      expect(
        controller.entries.any((entry) => entry.title == '工作树不可用'),
        isTrue,
      );
      controller.dispose();
    },
  );

  test('ignores a stale resume after quickly switching tasks', () async {
    final server = FakeCodexAppServer();
    final firstResume = Completer<JsonMap>();
    server.resumeCompleters['thread-1'] = firstResume;
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await controller.waitForInitialConfiguration();
    controller.status = RuntimeStatus.ready;

    final first = controller.resumeThread(protocolThread(id: 'thread-1'));
    await Future<void>.delayed(Duration.zero);
    // Model a second selection arriving while the first protocol call is
    // still pending; the production sidebar may re-enable switching after a
    // runtime status update before the original future settles.
    controller.status = RuntimeStatus.ready;
    await controller.resumeThread(protocolThread(id: 'thread-2'));

    expect(controller.activeThreadId, 'thread-2');
    expect(controller.isResumingThread, isFalse);
    firstResume.complete(server.resumeResult);
    await first;

    expect(controller.activeThreadId, 'thread-2');
    expect(controller.isResumingThread, isFalse);
    controller.dispose();
  });

  test('sends resumed follow-up turns to the bound managed worktree', () async {
    final root = await Directory.systemTemp.createTemp('worktree-follow-up-');
    addTearDown(() => root.delete(recursive: true));
    final source = await Directory('${root.path}/source').create();
    final worktree = await Directory('${root.path}/worktree').create();
    final store = RuntimeConfigurationStore(
      storage: CodexKeychainStorage(developmentDirectory: root),
    );
    await store.saveWorktreeRecords([
      LocalWorktreeRecord(
        worktreeId: 'task-1',
        projectId: 'project-1',
        sourceRepository: source.path,
        worktreePath: worktree.path,
        baseCommit: 'abc123',
        state: LocalWorktreeState.ready,
        createdAt: DateTime.now(),
      ),
    ]);
    await store.saveThreadEnvironmentBindings([
      ThreadEnvironmentBinding(
        threadId: 'thread-1',
        kind: ThreadEnvironmentKind.managedWorktree,
        workingDirectory: worktree.path,
        worktreeId: 'task-1',
      ),
    ]);
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: store,
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = source.path
      ..status = RuntimeStatus.ready;

    await controller.resumeThread(protocolThread(id: 'thread-1'));

    expect(await controller.sendPrompt('继续处理'), isTrue);
    expect(server.startedTurnDirectory, await worktree.resolveSymbolicLinks());
    controller.dispose();
  });

  test('rejects worktree branch changes while any task is running', () async {
    final git = FakeGitProjectService();
    final controller =
        CodexController(server: FakeCodexAppServer(), gitProjectService: git)
          ..workspacePath = '/worktree'
          ..status = RuntimeStatus.running;

    expect(
      await controller.createAndCheckoutGitBranch(
        'feature/blocked',
        workspace: '/worktree',
      ),
      isFalse,
    );
    expect(git.createdBranch, isNull);
    expect(controller.gitOperationError, contains('运行期间'));
    controller.dispose();
  });

  test(
    'rejects scheduled prompts while a thread uses a managed worktree',
    () async {
      final root = await Directory.systemTemp.createTemp('worktree-schedule-');
      addTearDown(() => root.delete(recursive: true));
      final source = await Directory('${root.path}/source').create();
      final worktree = await Directory('${root.path}/worktree').create();
      final store = RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      );
      await store.saveWorktreeRecords([
        LocalWorktreeRecord(
          worktreeId: 'wt-1',
          projectId: 'project-1',
          sourceRepository: source.path,
          worktreePath: worktree.path,
          baseCommit: 'abc123',
          state: LocalWorktreeState.ready,
          createdAt: DateTime.now(),
          threadId: 'thread-1',
        ),
      ]);
      await store.saveThreadEnvironmentBindings([
        ThreadEnvironmentBinding(
          threadId: 'thread-1',
          kind: ThreadEnvironmentKind.managedWorktree,
          workingDirectory: worktree.path,
          worktreeId: 'wt-1',
        ),
      ]);
      final now = DateTime(2030, 1, 2, 9);
      final controller =
          CodexController(
              server: FakeCodexAppServer(),
              runtimeConfigurationStore: store,
              clock: CodexClock(now: () => now),
            )
            ..workspacePath = source.path
            ..status = RuntimeStatus.ready;
      await controller.resumeThread(protocolThread(id: 'thread-1'));

      expect(
        await controller.schedulePrompt(
          prompt: '不应绑定到聊天工作树',
          runAt: now.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
      expect(controller.scheduledTasks, isEmpty);
      controller.dispose();
    },
  );

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
}
