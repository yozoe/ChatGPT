import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/browser_link_open_mode.dart';
import 'package:chatgpt/src/domain/pending_approval.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_approval_panel.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_error_policy.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_url_normalizer.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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

  test(
    'routes the official dynamic browser tool call through approval',
    () async {
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
          method: 'item/tool/call',
          requestId: 'dynamic-browser-1',
          params: {
            'tool': 'browser.open',
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'arguments': {'url': 'https://example.com/from-tool'},
          },
        ),
      );

      expect(controller.pendingApproval?.kind, ApprovalKind.browser);
      expect(openedUrl, isNull);

      await controller.respondToApproval(accepted: true);

      expect(openedUrl, 'https://example.com/from-tool');
      expect(writes.single['id'], 'dynamic-browser-1');
      expect(writes.single['result'], {
        'success': true,
        'contentItems': const <JsonMap>[],
      });
    },
  );

  test(
    'replays an approved browser call when the workspace handler reattaches',
    () async {
      final writes = <JsonMap>[];
      final controller = CodexController(
        server: CodexAppServer(messageSink: writes.add),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      addTearDown(controller.dispose);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/tool/call',
          requestId: 'dynamic-browser-queued',
          params: {
            'callId': 'call-queued',
            'threadId': 'thread-queued',
            'turnId': 'turn-queued',
            'tool': 'browser.open',
            'arguments': {'url': 'https://example.com/queued'},
          },
        ),
      );

      await controller.respondToApproval(accepted: true);
      expect(writes.single['result'], {
        'success': true,
        'contentItems': const <JsonMap>[],
      });

      final opened = <String>[];
      controller.setBrowserInvocationHandler(opened.add);
      expect(opened, ['https://example.com/queued']);
    },
  );

  test(
    'declines a dynamic browser tool call when browser access is disabled',
    () async {
      final writes = <JsonMap>[];
      final controller = CodexController(
        server: CodexAppServer(messageSink: writes.add),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      addTearDown(controller.dispose);
      await controller.setBrowserEnabled(false);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/tool/call',
          requestId: 'dynamic-browser-disabled',
          params: {
            'tool': 'browser.navigate',
            'arguments': {'url': 'https://example.com/disabled'},
          },
        ),
      );

      expect(writes.single['id'], 'dynamic-browser-disabled');
      expect(writes.single['result'], {
        'success': false,
        'contentItems': [
          {'type': 'inputText', 'text': '浏览器调用已被用户拒绝。'},
        ],
      });
      expect(controller.pendingApproval, isNull);
    },
  );

  test(
    'reuses a session grant for subsequent dynamic browser tool calls',
    () async {
      final writes = <JsonMap>[];
      final controller = CodexController(
        server: CodexAppServer(messageSink: writes.add),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      addTearDown(controller.dispose);
      final opened = <String>[];
      controller.setBrowserInvocationHandler(opened.add);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/tool/call',
          requestId: 'dynamic-browser-grant',
          params: {
            'tool': 'browser.open',
            'arguments': {'url': 'https://example.com/grant'},
          },
        ),
      );
      await controller.respondToApproval(accepted: true, allowSimilar: true);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/tool/call',
          requestId: 'dynamic-browser-follow-up',
          params: {
            'tool': 'browser.navigate',
            'arguments': {'url': 'https://example.com/follow-up'},
          },
        ),
      );

      expect(opened, [
        'https://example.com/grant',
        'https://example.com/follow-up',
      ]);
      expect(controller.pendingApproval, isNull);
      expect(writes.map((message) => message['id']), [
        'dynamic-browser-grant',
        'dynamic-browser-follow-up',
      ]);
    },
  );

  test(
    'accepts namespaced dynamic browser tools with encoded arguments',
    () async {
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
          method: 'item/tool/call',
          requestId: 'dynamic-browser-namespaced',
          params: {
            'namespace': 'browser',
            'tool': 'open',
            'arguments': '{"url":"https://example.com/namespaced"}',
          },
        ),
      );

      expect(controller.pendingApproval?.kind, ApprovalKind.browser);
      await controller.respondToApproval(accepted: true);

      expect(openedUrl, 'https://example.com/namespaced');
      expect(writes.single['result'], {
        'success': true,
        'contentItems': const <JsonMap>[],
      });
    },
  );

  test('accepts colon-delimited dynamic browser tool names', () async {
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
        method: 'item/tool/call',
        requestId: 'dynamic-browser-colon',
        params: {
          'tool': 'browser:open',
          'arguments': {'url': 'https://example.com/colon'},
        },
      ),
    );

    expect(controller.pendingApproval?.kind, ApprovalKind.browser);
    await controller.respondToApproval(accepted: true);

    expect(openedUrl, 'https://example.com/colon');
    expect(writes.single['result'], {
      'success': true,
      'contentItems': const <JsonMap>[],
    });
  });

  test('allows subsequent browser requests for the runtime session', () async {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    addTearDown(controller.dispose);
    final opened = <String>[];
    controller.setBrowserInvocationHandler(opened.add);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'browser/open',
        requestId: 'browser-session-first',
        params: {'url': 'https://example.com/first'},
      ),
    );
    await controller.respondToApproval(accepted: true, allowSimilar: true);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'browser/navigate',
        requestId: 'browser-session-second',
        params: {'url': 'https://example.com/second'},
      ),
    );

    expect(controller.pendingApproval, isNull);
    expect(opened, ['https://example.com/first', 'https://example.com/second']);
    expect(writes.map((message) => message['id']), [
      'browser-session-first',
      'browser-session-second',
    ]);
    expect(
      writes.map((message) => message['result']),
      everyElement({'accepted': true, 'scope': 'session'}),
    );
  });

  test('clears the browser session grant when the runtime exits', () async {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    addTearDown(controller.dispose);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'browser/open',
        requestId: 'browser-session-grant',
        params: {'url': 'https://example.com/grant'},
      ),
    );
    await controller.respondToApproval(accepted: true, allowSimilar: true);
    controller.handleServerEventForTesting(
      const ServerEvent(method: 'runtime/exited', params: {'code': 1}),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'browser/open',
        requestId: 'browser-after-restart',
        params: {'url': 'https://example.com/after-restart'},
      ),
    );

    expect(controller.pendingApproval?.requestId, 'browser-after-restart');
  });

  test('persists the user preference for Markdown web links', () async {
    final store = FakeRuntimeConfigurationStore();
    final firstController = CodexController(runtimeConfigurationStore: store);
    await firstController.waitForInitialConfiguration();
    await firstController.setBrowserLinkOpenMode(BrowserLinkOpenMode.inApp);
    expect(store.savedBrowserLinkOpenMode, BrowserLinkOpenMode.inApp);
    firstController.dispose();

    final restoredController = CodexController(
      runtimeConfigurationStore: store,
    );
    await restoredController.waitForInitialConfiguration();
    expect(restoredController.browserLinkOpenMode, BrowserLinkOpenMode.inApp);
    restoredController.dispose();
  });

  test('persists browser download and tab restore preferences', () async {
    final store = FakeRuntimeConfigurationStore();
    final controller = CodexController(runtimeConfigurationStore: store);
    await controller.waitForInitialConfiguration();
    await controller.setBrowserDownloadDirectory('/tmp/browser-downloads');
    await controller.setBrowserAskBeforeDownload(false);
    await controller.setBrowserRestoreTabs(true);

    expect(store.savedBrowserDownloadDirectory, '/tmp/browser-downloads');
    expect(store.savedBrowserAskBeforeDownload, isFalse);
    expect(store.savedBrowserRestoreTabs, isTrue);
    controller.dispose();
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

  test('resolves omnibox input to a URL or secure web search', () {
    expect(
      browserLocationForInput('example.com/docs').toString(),
      'https://example.com/docs',
    );
    expect(
      browserLocationForInput('flutter desktop browser')?.host,
      'www.google.com',
    );
    expect(
      browserLocationForInput('flutter desktop browser')?.queryParameters['q'],
      'flutter desktop browser',
    );
    expect(browserLocationForInput('file:///tmp/private'), isNull);
  });

  test('does not surface a cancelled WKWebView navigation as an error', () {
    final cancelled = WebResourceError(
      type: WebResourceErrorType.CANCELLED,
      description:
          'The operation couldn\'t be completed. (NSURLErrorDomain error -999.)',
    );
    final networkFailure = WebResourceError(
      type: WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
      description: 'Could not connect to the server.',
    );

    expect(shouldReportBrowserWebResourceError(cancelled), isFalse);
    expect(shouldReportBrowserWebResourceError(networkFailure), isTrue);
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

  testWidgets('declines a browser permission request with Escape', (
    tester,
  ) async {
    var declines = 0;
    const approval = PendingApproval(
      requestId: 45,
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
            onDecline: () async => declines++,
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(declines, 1);
  });

  testWidgets('clears only the selected browser data ranges', (tester) async {
    final cleared = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () {},
          clearWebsiteData: () async => cleared.add('website'),
          clearCache: () async => cleared.add('cache'),
          clearNavigationHistory: () async => cleared.add('history'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('browser-more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除浏览数据'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('browser-clear-website-data')));
    await tester.tap(find.byKey(const Key('browser-clear-history-data')));
    await tester.tap(find.byKey(const Key('browser-clear-download-data')));
    await tester.tap(find.text('清除').last);
    await tester.pumpAndSettle();

    expect(cleared, ['cache']);
    expect(find.textContaining('已清除所选浏览数据'), findsOneWidget);
  });

  testWidgets('reports native browser data cleanup failures', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () {},
          clearCache: () async => throw StateError('cache unavailable'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('browser-more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除浏览数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('browser-clear-website-data')));
    await tester.tap(find.byKey(const Key('browser-clear-history-data')));
    await tester.tap(find.byKey(const Key('browser-clear-download-data')));
    await tester.tap(find.text('清除').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('部分浏览数据清除失败：缓存'), findsOneWidget);
  });
}
