import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
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

  late FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    runtimeConfigurationStore = FakeRuntimeConfigurationStore();
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingRuntimeConfigurationStore = null;
  });

  test('automatically connects a restored primary workspace', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-auto-restore-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = ManagedRuntimeFakeServer()
      ..listResponse = [
        {'id': 'connected-thread', 'preview': 'connected'},
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore()
        ..workspace = primary.path,
    );

    await controller.connectRestoredWorkspace();

    expect(controller.status, RuntimeStatus.ready);
    expect(server.startCalls, 1);
    expect(server.runtimeDirectory, await primary.resolveSymbolicLinks());
    controller.dispose();
  });

  test('keeps cached task selection responsive while runtime starts', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-startup-task-selection-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = BlockingRuntimeFakeServer();
    final controller = CodexController(server: server)
      ..workspacePath = primary.path
      ..threads = [
        threadForTest(id: 'cached-a'),
        threadForTest(id: 'cached-b'),
      ];

    final startup = controller.startRuntime();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, RuntimeStatus.starting);
    expect(controller.canSwitchThreads, isTrue);

    await controller.resumeThread(controller.threads.last);
    expect(controller.activeThreadId, 'cached-b');
    expect(server.resumeCalls, 0);

    server.probeCompleter.complete(
      const CodexRuntimeProbe(isAvailable: true, executablePath: '/fake/codex'),
    );
    await startup;
    expect(server.resumedThreadId, 'cached-b');
    controller.dispose();
  });

  test(
    'automatically reconnects after changing the primary workspace',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-auto-switch-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory(
        '${root.path}/first',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second',
      ).create(recursive: true);
      final additional = await Directory(
        '${root.path}/additional',
      ).create(recursive: true);
      final server = ManagedRuntimeFakeServer()
        ..listResponse = [
          {'id': 'connected-thread', 'preview': 'connected'},
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();

      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      expect(controller.status, RuntimeStatus.ready);
      expect(server.startCalls, 1);
      expect(server.stopCalls, 0);

      await controller.addWorkspaceRoot(additional.path);
      expect(server.stopCalls, 0);
      expect(await controller.selectWorkspaceAndReconnect(second.path), isTrue);
      expect(controller.status, RuntimeStatus.ready);
      expect(server.stopCalls, 0);
      expect(server.startCalls, 1);
      expect(server.configReadDirectory, await second.resolveSymbolicLinks());
      expect(controller.workspaceConfigurations, hasLength(2));
      expect(controller.additionalWorkspacePaths, isEmpty);

      controller.status = RuntimeStatus.running;
      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      expect(controller.workspacePath, await first.resolveSymbolicLinks());
      expect(server.stopCalls, 0);
      expect(server.startCalls, 1);
      controller.dispose();
    },
  );

  test('reconnects after a successful CLI recheck from failure', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-runtime-recheck-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = ManagedRuntimeFakeServer()
      ..listResponse = [
        {'id': 'connected-thread', 'preview': 'connected'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = primary.path
      ..status = RuntimeStatus.failed;

    await controller.inspectRuntime();

    expect(controller.status, RuntimeStatus.ready);
    expect(server.startCalls, 1);
    controller.dispose();
  });

  test('automatically reconnects after an unexpected runtime exit', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-runtime-exit-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = ManagedRuntimeFakeServer()
      ..listResponse = [
        {'id': 'connected-thread', 'preview': 'connected'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = primary.path
      ..status = RuntimeStatus.ready;

    controller.handleServerEventForTesting(
      const ServerEvent(method: 'runtime/exited', params: {'code': 1}),
    );
    expect(controller.status, RuntimeStatus.failed);

    for (var attempt = 0; attempt < 120; attempt++) {
      if (controller.status == RuntimeStatus.ready) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    expect(controller.status, RuntimeStatus.ready);
    expect(server.startCalls, 1);
    controller.dispose();
  });

  test('cancels an in-flight automatic connection on dispose', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-runtime-dispose-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = BlockingRuntimeFakeServer();
    final controller = CodexController(server: server)
      ..workspacePath = primary.path;

    final connection = controller.startRuntime();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, RuntimeStatus.starting);
    controller.dispose();
    server.probeCompleter.complete(const CodexRuntimeProbe(isAvailable: true));

    await connection;

    expect(server.startCalls, 0);
  });

  test(
    'restores, canonicalizes, and deduplicates additional workspaces',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-workspaces-',
      );
      addTearDown(() => root.delete(recursive: true));
      final primary = await Directory(
        '${root.path}/primary',
      ).create(recursive: true);
      final additional = await Directory(
        '${root.path}/additional',
      ).create(recursive: true);
      final alias = Link('${root.path}/additional-alias');
      await alias.create(additional.path);
      final store = FakeRuntimeConfigurationStore()
        ..workspace = primary.path
        ..additionalWorkspaces = [
          additional.path,
          alias.path,
          '${root.path}/missing',
          primary.path,
        ];

      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();

      expect(controller.workspacePath, await primary.resolveSymbolicLinks());
      expect(controller.additionalWorkspacePaths, [
        await additional.resolveSymbolicLinks(),
      ]);
      expect(store.savedAdditionalWorkspaces, [
        await additional.resolveSymbolicLinks(),
      ]);
      expect(controller.workspaceConfigurations, hasLength(1));
      expect(controller.workspaceConfigurations.single.additionalPaths, [
        await additional.resolveSymbolicLinks(),
      ]);
      expect(store.savedWorkspaces, hasLength(1));
      controller.dispose();
    },
  );

  test(
    'adds and removes additional directories without disconnecting runtime',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-workspace-add-',
      );
      addTearDown(() => root.delete(recursive: true));
      final primary = await Directory(
        '${root.path}/primary',
      ).create(recursive: true);
      final first = await Directory(
        '${root.path}/first',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second',
      ).create(recursive: true);
      final store = FakeRuntimeConfigurationStore();
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();

      await controller.selectWorkspace(primary.path);
      await controller.addWorkspaceRoot(first.path);
      await controller.addWorkspaceRoot(second.path);
      await controller.addWorkspaceRoot(first.path);

      expect(controller.workspaceRoots, [
        await primary.resolveSymbolicLinks(),
        await first.resolveSymbolicLinks(),
        await second.resolveSymbolicLinks(),
      ]);
      expect(
        store.savedAdditionalWorkspaces,
        controller.additionalWorkspacePaths,
      );

      controller.status = RuntimeStatus.ready;
      await controller.removeWorkspaceRoot(
        controller.additionalWorkspacePaths.first,
      );
      expect(controller.additionalWorkspacePaths, [
        await second.resolveSymbolicLinks(),
      ]);
      expect(store.savedAdditionalWorkspaces, [
        await second.resolveSymbolicLinks(),
      ]);
      controller.dispose();
    },
  );

  test('serializes additional workspace persistence snapshots', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-workspace-save-',
    );
    addTearDown(() => root.delete(recursive: true));
    final primary = await Directory(
      '${root.path}/primary',
    ).create(recursive: true);
    final first = await Directory('${root.path}/first').create(recursive: true);
    final second = await Directory(
      '${root.path}/second',
    ).create(recursive: true);
    final store = DelayedAdditionalWorkspaceStore();
    final controller = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    )..workspacePath = primary.path;
    await controller.waitForInitialConfiguration();

    final firstSave = controller.addWorkspaceRoot(first.path);
    while (store.saveCompleters.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final secondSave = controller.addWorkspaceRoot(second.path);
    await Future<void>.delayed(Duration.zero);

    expect(store.savedSnapshots, [
      [await first.resolveSymbolicLinks()],
    ]);

    store.saveCompleters.first.complete();
    while (store.saveCompleters.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(store.savedSnapshots.last, [
      await first.resolveSymbolicLinks(),
      await second.resolveSymbolicLinks(),
    ]);
    store.saveCompleters.last.complete();
    await Future.wait([firstSave, secondSave]);
    controller.dispose();
  });
}
