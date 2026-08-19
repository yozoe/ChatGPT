import 'package:chatgpt/src/app.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/relay_provider_configuration.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Codex Desk shell', (tester) async {
    await tester.pumpWidget(const CodexDeskApp());

    expect(find.text('Codex Desk'), findsOneWidget);
    expect(find.text('选择一个本地项目'), findsOneWidget);
    expect(find.text('任务控制台'), findsOneWidget);
  });

  test(
    'classifies server approval requests before JSON-RPC responses',
    () async {
      final server = CodexAppServer();
      final eventFuture = server.events.first;

      server.handleStdoutLineForTesting('''
      {"id": "approval-1", "method": "item/fileChange/requestApproval",
       "params": {"threadId": "thread-1", "turnId": "turn-1"}}
    ''');

      final event = await eventFuture;
      expect(event.isServerRequest, isTrue);
      expect(event.requestId, 'approval-1');
      expect(event.method, 'item/fileChange/requestApproval');
      await server.dispose();
    },
  );

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
    controller.dispose();
  });

  test('coalesces agent deltas into one timeline entry', () async {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'message-1', 'delta': 'Hello'},
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'message-1', 'delta': ' world'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final agentEntries = controller.entries
        .where((entry) => entry.kind == TimelineKind.agent)
        .toList();
    expect(agentEntries, hasLength(1));
    expect(agentEntries.single.detail, 'Hello world');
    controller.dispose();
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

  test('updates visible account state from App Server notifications', () {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'account/updated',
        params: {'authMode': 'chatgpt', 'planType': 'plus'},
      ),
    );

    expect(controller.authStatus, AuthStatus.chatgpt);
    expect(controller.authLabel, 'ChatGPT plus');
    controller.dispose();
  });

  test(
    'builds a Responses-only relay configuration without leaking its key',
    () {
      const relay = RelayProviderConfiguration(
        baseUrl: 'https://relay.example.com/v1',
        model: 'codex-compatible-model',
        apiKey: 'relay-secret',
      );

      expect(relay.processEnvironment, {
        RelayProviderConfiguration.environmentVariable: 'relay-secret',
      });
      expect(relay.threadConfig, {
        'model_providers': {
          RelayProviderConfiguration.providerId: {
            'name': 'Codex Desk Relay',
            'base_url': 'https://relay.example.com/v1',
            'env_key': RelayProviderConfiguration.environmentVariable,
            'wire_api': 'responses',
          },
        },
      });
    },
  );

  test('only permits HTTPS relay URLs except localhost', () {
    expect(
      () => RelayProviderConfiguration.normalizeBaseUrl('http://relay.test/v1'),
      throwsFormatException,
    );
    expect(
      RelayProviderConfiguration.normalizeBaseUrl('http://localhost:8080/v1/'),
      'http://localhost:8080/v1',
    );
  });
}
