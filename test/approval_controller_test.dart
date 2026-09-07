import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/commandExecution/requestApproval',
        requestId: 43,
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'reason': '需要重复执行同类命令',
          'command': 'touch demo.txt',
        },
      ),
    );
    await controller.respondToApproval(accepted: true, allowSimilar: true);
    expect(writes.last, {
      'id': 43,
      'result': {'decision': 'acceptForSession'},
    });

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/fileChange/requestApproval',
        requestId: 44,
        params: {'threadId': 'thread-1', 'turnId': 'turn-1'},
      ),
    );
    await controller.respondToApproval(accepted: true, allowSimilar: true);
    expect(writes.last, {
      'id': 44,
      'result': {'decision': 'accept'},
    });
    controller.dispose();
  });

  test(
    'automatically approves supported requests in auto approval mode',
    () async {
      final writes = <JsonMap>[];
      final controller = CodexController(
        server: CodexAppServer(messageSink: writes.add),
      );

      await controller.setApprovalMode(ApprovalMode.autoApprove);
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
    },
  );

  test('uses the unified approval mode labels', () {
    expect(ApprovalMode.manual.label, '请求批准');
    expect(ApprovalMode.autoApprove.label, '帮我批准');
  });

  test('persists and restores the approval mode', () async {
    final store = FakeRuntimeConfigurationStore();
    final firstController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );

    await firstController.waitForInitialConfiguration();
    await firstController.setApprovalMode(ApprovalMode.autoApprove);

    expect(store.savedApprovalMode, ApprovalMode.autoApprove.name);
    firstController.dispose();

    final restoredController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );
    await restoredController.waitForInitialConfiguration();

    expect(restoredController.approvalMode, ApprovalMode.autoApprove);
    await restoredController.setApprovalMode(ApprovalMode.manual);
    expect(store.savedApprovalMode, ApprovalMode.manual.name);
    restoredController.dispose();

    final defaultRestoredController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );
    await defaultRestoredController.waitForInitialConfiguration();

    expect(defaultRestoredController.approvalMode, ApprovalMode.manual);
    defaultRestoredController.dispose();
  });
}
