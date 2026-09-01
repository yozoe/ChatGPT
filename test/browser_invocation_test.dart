import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/pending_approval.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_approval_panel.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_url_normalizer.dart';
import 'widget_fakes/fake_runtime_configuration_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('does not navigate for an informational browser item', () async {
    final controller = CodexController(
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    addTearDown(controller.dispose);
    String? openedUrl;
    controller.setBrowserInvocationHandler((url) => openedUrl = url);

    const event = ServerEvent(
      method: 'item/started',
      params: {
        'item': {
          'id': 'browser-1',
          'type': 'browser',
          'url': 'https://example.com/docs',
        },
      },
    );
    controller.handleServerEventForTesting(event);

    expect(openedUrl, isNull);
  });

  test('does not navigate for an informational computer-use item', () async {
    final controller = CodexController(
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    addTearDown(controller.dispose);
    String? openedUrl;
    controller.setBrowserInvocationHandler((url) => openedUrl = url);
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'item': {
            'id': 'browser-2',
            'type': 'computer-use',
            'action': {'url': 'https://example.com'},
          },
        },
      ),
    );

    expect(openedUrl, isNull);
  });

  test('shows a browser permission request before opening', () async {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    addTearDown(controller.dispose);
    String? openedUrl;
    controller.setBrowserInvocationHandler((url) => openedUrl = url);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'browser/open',
        requestId: 42,
        params: {'url': 'https://example.com'},
      ),
    );
    expect(controller.pendingApproval?.kind, ApprovalKind.browser);
    expect(openedUrl, isNull);

    await controller.respondToApproval(accepted: true);
    expect(openedUrl, 'https://example.com');
    expect(writes.single['id'], 42);
    expect(writes.single['result'], {'accepted': true, 'scope': 'turn'});
  });

  testWidgets(
    'accepts nested browser URLs and exposes them to the approval UI',
    (tester) async {
      final controller = CodexController(
        server: CodexAppServer(messageSink: (_) {}),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'browser/navigate',
          requestId: 'nested-browser-url',
          params: {
            'payload': {
              'request': {'target_url': 'https://example.com/nested'},
            },
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(
        find.text('允许 ChatGPT 访问 https://example.com/nested？'),
        findsOneWidget,
      );
    },
  );

  test('rejects browser URLs without an authority', () {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    addTearDown(controller.dispose);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'browser/open',
        requestId: 'invalid-browser-url',
        params: {'url': 'https:'},
      ),
    );

    expect(controller.pendingApproval, isNull);
    expect(writes, hasLength(1));
    expect(writes.single['id'], 'invalid-browser-url');
    expect(writes.single['error'], isA<Map>());
  });

  test('rejects loopback, private, link-local and malformed browser hosts', () {
    final blocked = <String>[
      'http://localhost:3000',
      'http://127.0.0.1:8080',
      'http://10.0.0.1',
      'http://172.16.0.1',
      'http://192.168.1.1',
      'http://169.254.169.254/latest',
      'http://[::1]/',
      'http://[::ffff:127.0.0.1]/',
      'https://:443',
    ];
    for (final value in blocked) {
      expect(normalizeBrowserUrl(value), isNull, reason: value);
    }
    expect(normalizeBrowserUrl('https://example.com'), isNotNull);
  });

  testWidgets('replays an approved navigation when the URL is unchanged', (
    tester,
  ) async {
    final controller = CodexController(
      server: CodexAppServer(messageSink: (_) {}),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    for (final requestId in const ['same-url-first', 'same-url-second']) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'browser/navigate',
          requestId: requestId,
          params: const {'url': 'https://example.com/reload'},
        ),
      );
      await controller.respondToApproval(accepted: true);
      await tester.pump();
    }

    final page = tester.widget<BrowserWorkspacePage>(
      find.byType(BrowserWorkspacePage),
    );
    expect(page.initialUrl, 'https://example.com/reload');
    expect(page.navigationRevision, 2);
  });

  test(
    'clears browser navigation de-duplication after runtime restart',
    () async {
      final controller = CodexController(
        server: CodexAppServer(messageSink: (_) {}),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      addTearDown(controller.dispose);
      final opened = <String>[];
      controller.setBrowserInvocationHandler(opened.add);

      void request() {
        controller.handleServerEventForTesting(
          const ServerEvent(
            method: 'browser/open',
            requestId: 'reused-request-id',
            params: {'url': 'https://example.com/reused'},
          ),
        );
      }

      request();
      await controller.respondToApproval(accepted: true);
      controller.handleServerEventForTesting(
        const ServerEvent(method: 'runtime/exited', params: {'code': 1}),
      );
      request();
      await controller.respondToApproval(accepted: true);

      expect(opened, [
        'https://example.com/reused',
        'https://example.com/reused',
      ]);
    },
  );

  test(
    'disabling browser access declines and clears pending browser approvals',
    () async {
      final writes = <JsonMap>[];
      final controller = CodexController(
        server: CodexAppServer(messageSink: writes.add),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      addTearDown(controller.dispose);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'browser/open',
          requestId: 'browser-pending-one',
          params: {'url': 'https://example.com/one'},
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'browser/navigate',
          requestId: 'browser-pending-two',
          params: {'url': 'https://example.com/two'},
        ),
      );

      await controller.setBrowserEnabled(false);

      expect(controller.pendingApproval, isNull);
      expect(writes.map((message) => message['id']), [
        'browser-pending-one',
        'browser-pending-two',
      ]);
      expect(
        writes.map((message) => message['result']),
        everyElement({'accepted': false, 'scope': 'turn'}),
      );
    },
  );

  testWidgets('renders Codex-style browser permission actions', (tester) async {
    final controller = CodexController(
      server: CodexAppServer(messageSink: (_) {}),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'browser/open',
        requestId: 43,
        params: {'url': 'https://example.com'},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    expect(find.text('Browser'), findsNWidgets(2));
    expect(find.text('允许 ChatGPT 访问 https://example.com？'), findsOneWidget);
    expect(find.byKey(const Key('approval-allow-all-sites')), findsOneWidget);
    expect(find.text('允许一次  ↵'), findsOneWidget);
    expect(find.text('拒绝  Esc'), findsOneWidget);
  });

  testWidgets('wraps browser permission actions in a narrow viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const approval = PendingApproval(
      requestId: 44,
      method: 'browser/open',
      kind: ApprovalKind.browser,
      params: {'url': 'https://example.com'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovalPanel(
            approval: approval,
            taskLabel: null,
            enabled: true,
            onAccept: () async {},
            onAllowSimilar: () async {},
            onDecline: () async {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
