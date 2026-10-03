import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/browser_link_open_mode.dart';
import 'package:chatgpt/src/domain/browser_tab_snapshot.dart';
import 'package:chatgpt/src/domain/pending_approval.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_approval_panel.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart';
import 'package:chatgpt/src/presentation/browser/browser_download_cancellation.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_error_policy.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_url_normalizer.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'widget_fakes/fake_runtime_configuration_store.dart';
import 'widget_fakes/fake_browser_session_store.dart';

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

  testWidgets('ignores callbacks that arrive after a tab is closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    final staleUrl = WebUri('https://example.com/stale');
    final staleError = WebResourceError(
      type: WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
      description: 'late closed-tab failure',
    );

    await tester.tap(find.byKey(const Key('browser-new-tab')));
    await tester.pump();
    state.handleNavigationStarted(0, staleUrl);
    await tester.tap(find.byKey(const ValueKey('browser-close-tab-0')));
    await tester.pump();

    state.handleNavigationStopped(0, staleUrl);
    state.handleNavigationError(
      0,
      WebResourceRequest(url: staleUrl, isForMainFrame: true),
      staleError,
    );
    state.handleTitleChanged(0, '迟到标题');
    state.handleVisitedHistoryUpdate(0, staleUrl);
    await tester.pump();

    expect(find.text('late closed-tab failure'), findsNothing);
    expect(find.text('迟到标题'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not commit a download after its tab is closed', (
    tester,
  ) async {
    final transfer = Completer<String?>();
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () {},
          urlSafetyChecker: (_) async => true,
          downloadSaver:
              ({
                required request,
                required urlSafetyChecker,
                required pickLocation,
                downloadDirectory,
                askForLocation = true,
                cancellation,
              }) => transfer.future,
        ),
      ),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    final download = DownloadStartRequest(
      url: WebUri('https://example.com/file.txt'),
      contentLength: 1,
      suggestedFilename: 'file.txt',
    );

    await tester.tap(find.byKey(const Key('browser-new-tab')));
    await tester.pump();
    final pending = state.handleDownloadStart(0, download, null);
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('browser-close-tab-0')));
    await tester.pump();
    transfer.complete('/tmp/file.txt');
    await pending;
    await tester.pump();

    expect(find.textContaining('下载已保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lets the browser banner cancel an active download', (
    tester,
  ) async {
    final transfer = Completer<String?>();
    BrowserDownloadCancellation? activeCancellation;
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () {},
          urlSafetyChecker: (_) async => true,
          downloadSaver:
              ({
                required request,
                required urlSafetyChecker,
                required pickLocation,
                downloadDirectory,
                askForLocation = true,
                BrowserDownloadCancellation? cancellation,
              }) {
                activeCancellation = cancellation;
                return transfer.future;
              },
        ),
      ),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    final download = DownloadStartRequest(
      url: WebUri('https://example.com/active.txt'),
      contentLength: 1,
      suggestedFilename: 'active.txt',
    );
    final pending = state.handleDownloadStart(0, download, null);
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pump();
    expect(activeCancellation, isNotNull);
    expect(find.byKey(const Key('browser-cancel-download')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('browser-download-banner')))
          .label,
      contains('下载状态：'),
    );

    await tester.tap(find.byKey(const Key('browser-cancel-download')));
    expect(activeCancellation!.isCancelled, isTrue);
    transfer.complete('/tmp/active.txt');
    await pending;
    await tester.pump();

    expect(find.text('已取消下载。'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('restores saved tabs through the navigation lifecycle', (
    tester,
  ) async {
    final navigated = <({int tabId, Uri uri})>[];
    final sessionStore = FakeBrowserSessionStore(
      snapshot: (
        tabs: const [
          BrowserTabSnapshot(url: 'https://example.com/one', title: 'One'),
          BrowserTabSnapshot(url: 'https://example.com/two', title: 'Two'),
        ],
        activeIndex: 1,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () {},
          restoreTabs: true,
          sessionStore: sessionStore,
          urlSafetyChecker: (_) async => true,
          restoreTabNavigation: (tabId, uri) async {
            navigated.add((tabId: tabId, uri: uri));
          },
        ),
      ),
    );
    await tester.pump();

    expect(navigated, [
      (tabId: 0, uri: Uri.parse('https://example.com/one')),
      (tabId: 1, uri: Uri.parse('https://example.com/two')),
    ]);
    expect(find.byKey(const Key('browser-tab-0')), findsOneWidget);
    expect(find.byKey(const Key('browser-tab-1')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      'https://example.com/two',
    );
  });

  testWidgets('drops a late restored-tab safety result after disposal', (
    tester,
  ) async {
    final safetyCheck = Completer<bool>();
    final navigated = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () {},
          restoreTabs: true,
          sessionStore: FakeBrowserSessionStore(
            snapshot: (
              tabs: const [
                BrowserTabSnapshot(
                  url: 'https://example.com/late',
                  title: 'Late',
                ),
              ],
              activeIndex: 0,
            ),
          ),
          urlSafetyChecker: (_) => safetyCheck.future,
          restoreTabNavigation: (_, uri) async => navigated.add(uri),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    safetyCheck.complete(true);
    await tester.pump();

    expect(navigated, isEmpty);
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

  testWidgets('exposes browser semantics and keyboard navigation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );

    final semanticsOwner =
        tester.binding.renderViews.single.owner!.semanticsOwner;
    expect(semanticsOwner, isNotNull);
    final semanticsData = <SemanticsData>[];
    bool collectSemantics(SemanticsNode node) {
      semanticsData.add(node.getSemanticsData());
      node.visitChildren(collectSemantics);
      return true;
    }

    final rootSemanticsNode = semanticsOwner!.rootSemanticsNode;
    expect(rootSemanticsNode, isNotNull);
    collectSemantics(rootSemanticsNode!);
    final labels = semanticsData.map((data) => data.label).toSet();
    expect(labels.any((label) => label.contains('内置浏览器工作区')), isTrue);
    expect(labels.any((label) => label.contains('标签页：新标签页')), isTrue);
    expect(labels.any((label) => label.contains('地址栏')), isTrue);
    expect(labels.any((label) => label.contains('网页内容')), isTrue);
    final unlabeledTapNodes = semanticsData
        .where(
          (data) =>
              data.hasAction(SemanticsAction.tap) &&
              data.label.trim().isEmpty &&
              data.tooltip.trim().isEmpty,
        )
        .toList(growable: false);
    expect(unlabeledTapNodes, isEmpty);

    expect(
      tester
          .getSemantics(find.byKey(const Key('browser-workspace-page')))
          .label,
      contains('内置浏览器工作区'),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('browser-tab-0'))).label,
      contains('标签页：新标签页'),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('browser-address'))).label,
      contains('地址栏'),
    );
    expect(tester.getSemantics(find.bySemanticsLabel('后退')).label, '后退');
    expect(tester.getSemantics(find.bySemanticsLabel('前进')).label, '前进');
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('刷新'))).label,
      contains('刷新'),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('新建标签页'))).label,
      contains('新建标签页'),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('browser-page-body'))).label,
      contains('网页内容'),
    );
    final state = tester.state<BrowserWorkspacePageState>(
      find.byType(BrowserWorkspacePage),
    );
    state.handleNavigationStarted(0, WebUri('https://example.com/failed'));
    state.handleNavigationError(
      0,
      WebResourceRequest(
        url: WebUri('https://example.com/failed'),
        isForMainFrame: true,
      ),
      WebResourceError(
        type: WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
        description: '无法连接测试地址',
      ),
    );
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const Key('browser-error-banner'))).label,
      contains('无法连接测试地址'),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.byKey(const Key('browser-tab-1')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.byKey(const Key('browser-tab-1')), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(tester.takeException(), isNull);
    semantics.dispose();
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
