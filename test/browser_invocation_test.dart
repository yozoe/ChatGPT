import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/pending_approval.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_approval_panel.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart';
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

  testWidgets('renders Codex browser chrome and manages local tabs', (
    tester,
  ) async {
    var returnedToConversation = false;
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () => returnedToConversation = true,
        ),
      ),
    );

    expect(find.text('新标签页'), findsOneWidget);
    expect(find.text('搜索或输入网址'), findsOneWidget);
    expect(find.text('开始浏览'), findsOneWidget);
    expect(find.byKey(const Key('browser-import-banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('browser-new-tab')));
    await tester.pump();
    expect(find.text('新标签页'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('browser-close-tab-1')));
    await tester.pump();
    expect(find.text('新标签页'), findsOneWidget);
    expect(returnedToConversation, isFalse);

    await tester.tap(find.byKey(const ValueKey('browser-close-tab-0')));
    expect(returnedToConversation, isTrue);
  });

  testWidgets('binds a webpage popup to its new browser tab', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    final popup = CreateWindowAction(
      windowId: 42,
      request: URLRequest(url: WebUri('https://1.1.1.1/popup')),
      isForMainFrame: true,
    );
    final handled = await state.handleCreateWindow(0, popup);
    await tester.pump();

    expect(handled, isTrue);
    expect(find.text('新标签页'), findsNWidgets(2));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      'https://1.1.1.1/popup',
    );
    expect(find.text('开始浏览'), findsNothing);
    expect(find.textContaining('浏览器尚未准备好'), findsNothing);

    expect(await state.handleCreateWindow(0, popup), isTrue);
    await tester.pump();
    expect(find.text('新标签页'), findsNWidgets(2));

    state.handleCloseWindow(1);
    await tester.pump();
    expect(find.text('新标签页'), findsOneWidget);

    expect(await state.handleCreateWindow(0, popup), isTrue);
    await tester.pump();
    expect(find.text('新标签页'), findsNWidgets(2));
  });

  testWidgets('consumes a blocked popup without replacing the opener', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () {},
          urlSafetyChecker: (_) async => false,
        ),
      ),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );

    final handled = await state.handleCreateWindow(
      0,
      CreateWindowAction(
        windowId: 91,
        request: URLRequest(url: WebUri('https://1.1.1.1/private')),
        isForMainFrame: true,
      ),
    );
    await tester.pump();

    expect(handled, isTrue);
    expect(find.text('新标签页'), findsOneWidget);
    expect(find.textContaining('已阻止指向本机或私有网络'), findsOneWidget);
  });

  testWidgets(
    'consumes a popup when its source tab closes during safety check',
    (tester) async {
      final safetyCheck = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: BrowserWorkspacePage(
            onOpenConversation: () {},
            urlSafetyChecker: (_) => safetyCheck.future,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('browser-new-tab')));
      await tester.pump();
      final state = tester.state<BrowserWorkspacePageState>(
        find.byType(BrowserWorkspacePage),
      );

      final handling = state.handleCreateWindow(
        1,
        CreateWindowAction(
          windowId: 92,
          request: URLRequest(url: WebUri('https://1.1.1.1/popup')),
          isForMainFrame: true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('browser-close-tab-1')));
      await tester.pump();
      safetyCheck.complete(true);

      expect(await handling, isTrue);
      await tester.pump();
      expect(find.text('新标签页'), findsOneWidget);
    },
  );

  testWidgets('ignores an older agent navigation after a newer revision', (
    tester,
  ) async {
    final firstCheck = Completer<bool>();
    final secondCheck = Completer<bool>();
    Future<bool> checkUrl(Uri uri) =>
        uri.path == '/first' ? firstCheck.future : secondCheck.future;
    Widget page(String path, int revision) => MaterialApp(
      home: BrowserWorkspacePage(
        onOpenConversation: () {},
        initialUrl: 'https://1.1.1.1$path',
        navigationRevision: revision,
        urlSafetyChecker: checkUrl,
      ),
    );

    await tester.pumpWidget(page('/first', 1));
    await tester.pumpWidget(page('/second', 2));
    secondCheck.complete(true);
    await tester.pump();
    firstCheck.complete(false);
    await tester.pump();

    expect(find.textContaining('已阻止无法确认安全性'), findsNothing);
  });

  testWidgets('ignores cancellation from an older page load', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    final firstUrl = WebUri('https://1.1.1.1/first');
    final secondUrl = WebUri('https://1.1.1.1/second');
    final cancelled = WebResourceError(
      type: WebResourceErrorType.CANCELLED,
      description: 'cancelled',
    );

    state.handleNavigationStarted(0, firstUrl);
    state.handleNavigationAuthorized(0, secondUrl);
    state.handleNavigationStarted(0, secondUrl);
    state.handleNavigationError(
      0,
      WebResourceRequest(url: firstUrl, isForMainFrame: true),
      cancelled,
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      secondUrl.toString(),
    );

    state.handleNavigationError(
      0,
      WebResourceRequest(url: secondUrl, isForMainFrame: true),
      cancelled,
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('finishes loading after a server redirect changes the URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    final initialUrl = WebUri('https://1.1.1.1/start');
    final redirectedUrl = WebUri('https://1.1.1.1/final');

    state.handleNavigationStarted(0, initialUrl);
    state.handleNavigationAuthorized(0, redirectedUrl);
    state.handleNavigationStopped(0, redirectedUrl);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      redirectedUrl.toString(),
    );
  });

  testWidgets('reports a redirected main-frame failure and stops loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    final initialUrl = WebUri('https://1.1.1.1/start');
    final redirectedUrl = WebUri('https://1.1.1.1/final');

    state.handleNavigationStarted(0, initialUrl);
    state.handleNavigationAuthorized(0, redirectedUrl);
    state.handleNavigationError(
      0,
      WebResourceRequest(url: redirectedUrl, isForMainFrame: true),
      WebResourceError(
        type: WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
        description: 'redirect failed',
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('redirect failed'), findsOneWidget);
  });

  testWidgets('ignores stale completion and failure from an older load', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    final firstUrl = WebUri('https://1.1.1.1/first');
    final secondUrl = WebUri('https://1.1.1.1/second');

    state.handleNavigationStarted(0, firstUrl);
    state.handleNavigationAuthorized(0, secondUrl);
    state.handleNavigationStarted(0, secondUrl);
    state.handleNavigationStopped(0, firstUrl);
    state.handleNavigationError(
      0,
      WebResourceRequest(url: firstUrl, isForMainFrame: true),
      WebResourceError(
        type: WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
        description: 'stale failure',
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('stale failure'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      secondUrl.toString(),
    );

    state.handleNavigationStopped(0, secondUrl);
    state.handleNavigationStopped(0, firstUrl);
    state.handleNavigationError(
      0,
      WebResourceRequest(url: firstUrl, isForMainFrame: true),
      WebResourceError(
        type: WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
        description: 'very late failure',
      ),
    );
    await tester.pump();

    expect(find.text('very late failure'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      secondUrl.toString(),
    );
  });

  testWidgets('a user navigation supersedes a pending agent safety check', (
    tester,
  ) async {
    final agentSafetyCheck = Completer<bool>();
    Future<bool> checkUrl(Uri uri) => uri.path == '/agent'
        ? agentSafetyCheck.future
        : Future<bool>.value(true);
    Widget page({String? initialUrl, int revision = 0}) => MaterialApp(
      home: BrowserWorkspacePage(
        onOpenConversation: () {},
        initialUrl: initialUrl,
        navigationRevision: revision,
        urlSafetyChecker: checkUrl,
      ),
    );

    await tester.pumpWidget(page());
    await tester.pumpWidget(
      page(initialUrl: 'https://1.1.1.1/agent', revision: 1),
    );
    await tester.enterText(
      find.byKey(const Key('browser-address')),
      'https://1.1.1.1/user',
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    await state.navigateFromAddress();
    agentSafetyCheck.complete(false);
    await tester.pump();

    expect(find.textContaining('浏览器尚未准备好'), findsOneWidget);
    expect(find.textContaining('已阻止无法确认安全性'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      'https://1.1.1.1/user',
    );
  });

  testWidgets('does not focus a new tab after the browser is disposed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );

    await tester.tap(find.byKey(const Key('browser-new-tab')));
    await tester.pumpWidget(const SizedBox());

    expect(tester.takeException(), isNull);
  });

  testWidgets('explains the Chrome import privacy boundary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );

    await tester.tap(find.byKey(const Key('browser-import-chrome')));
    await tester.pumpAndSettle();

    expect(find.text('浏览器数据保持独立'), findsOneWidget);
    expect(find.textContaining('不会读取 Chrome'), findsOneWidget);
  });

  testWidgets('keeps browser controls usable in a narrow workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );

    expect(find.byKey(const Key('browser-address')), findsOneWidget);
    expect(find.byKey(const Key('browser-new-tab')), findsOneWidget);
    expect(find.byKey(const Key('browser-more-menu')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
