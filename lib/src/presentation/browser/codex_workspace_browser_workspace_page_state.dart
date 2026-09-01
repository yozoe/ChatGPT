import 'dart:async';

import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_url_normalizer.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

/// 管理内置浏览器的原生控制器、导航状态和短生命周期错误反馈。
/// Owns the embedded browser's native controller, navigation state, and transient error feedback.
class BrowserWorkspacePageState extends State<BrowserWorkspacePage> {
  final TextEditingController _address = TextEditingController();
  InAppWebViewController? _webView;
  bool _loading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _error;

  /// 释放地址输入框；原生 WebView 由其 Widget 在移除时释放。
  /// Disposes the address field; the native WebView is released when its widget is removed.
  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  /// 提交地址栏内容，并只允许在内置浏览器加载 HTTP 或 HTTPS 页面。
  /// Submits the address field and only permits HTTP or HTTPS pages in the embedded browser.
  Future<void> navigateFromAddress() async {
    final uri = normalizeBrowserUrl(_address.text);
    if (uri == null) {
      setState(() => _error = '请输入有效的 HTTP 或 HTTPS 地址。');
      return;
    }
    final controller = _webView;
    if (controller == null) {
      setState(() => _error = '浏览器尚未准备好，请稍后重试。');
      return;
    }
    setState(() => _error = null);
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '无法加载此地址：$error');
    }
  }

  /// 在系统默认浏览器中打开当前已加载的页面。
  /// Opens the currently loaded page in the system default browser.
  Future<void> openInDefaultBrowser() async {
    final uri = normalizeBrowserUrl(_address.text);
    if (uri == null) {
      if (mounted) setState(() => _error = '请输入有效的 HTTP 或 HTTPS 地址。');
      return;
    }
    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (mounted) setState(() => _error = '无法在系统默认浏览器中打开此地址：$error');
      return;
    }
    if (!mounted || opened) return;
    setState(() => _error = '无法在系统默认浏览器中打开此地址。');
  }

  /// 回退到 WebView 的上一条导航记录，并刷新工具栏的可用状态。
  /// Navigates back in the WebView history and refreshes toolbar availability.
  Future<void> goBack() async {
    final controller = _webView;
    if (controller == null || !await controller.canGoBack()) return;
    try {
      await controller.goBack();
      await refreshNavigationState();
    } catch (error) {
      if (mounted) setState(() => _error = '后退失败：$error');
    }
  }

  /// 前进到 WebView 的下一条导航记录，并刷新工具栏的可用状态。
  /// Navigates forward in the WebView history and refreshes toolbar availability.
  Future<void> goForward() async {
    final controller = _webView;
    if (controller == null || !await controller.canGoForward()) return;
    try {
      await controller.goForward();
      await refreshNavigationState();
    } catch (error) {
      if (mounted) setState(() => _error = '前进失败：$error');
    }
  }

  /// 重新加载当前页面；加载中时停止当前导航。
  /// Reloads the current page, or stops its current navigation while loading.
  Future<void> reloadOrStop() async {
    final controller = _webView;
    if (controller == null) return;
    if (_loading) {
      try {
        await controller.stopLoading();
      } catch (error) {
        if (mounted) setState(() => _error = '停止加载失败：$error');
      }
      return;
    }
    try {
      await controller.reload();
    } catch (error) {
      if (mounted) setState(() => _error = '刷新失败：$error');
    }
  }

  /// 从原生控制器读取可前进/后退状态，避免异步结果写入已销毁页面。
  /// Reads back/forward availability from the native controller without updating a disposed page.
  Future<void> refreshNavigationState() async {
    final controller = _webView;
    if (controller == null) return;
    bool canGoBack;
    bool canGoForward;
    try {
      canGoBack = await controller.canGoBack();
      canGoForward = await controller.canGoForward();
    } catch (_) {
      return;
    }
    if (!mounted || !identical(controller, _webView)) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  /// 同步网页导航到地址栏，避免浏览器回调覆盖用户正在编辑的无效地址。
  /// Synchronizes a browser navigation into the address field.
  void updateUrl(WebUri? url) {
    if (!mounted || url == null) return;
    final value = url.toString();
    setState(() {
      _address.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      _error = null;
    });
    unawaited(refreshNavigationState());
  }

  /// 只将 HTTP 与 HTTPS 留在嵌入式页面，其余 scheme 明确交给系统处理。
  /// Keeps only HTTP and HTTPS in the embedded view and explicitly delegates other schemes to macOS.
  Future<NavigationActionPolicy?> decideNavigation(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url;
    if (url == null || isBrowserWebUri(url)) {
      return NavigationActionPolicy.ALLOW;
    }
    bool opened;
    try {
      opened = await launchUrl(
        Uri.parse(url.toString()),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '此地址无法在系统默认应用中打开：$error');
      return NavigationActionPolicy.CANCEL;
    }
    if (mounted && !opened) {
      setState(() => _error = '此地址无法在系统默认应用中打开。');
    }
    return NavigationActionPolicy.CANCEL;
  }

  /// 构建原生 WebView 创建前显示的无网络起始页。
  /// Builds the no-network start page shown before a native WebView navigation.
  InAppWebViewInitialData initialPage() => InAppWebViewInitialData(
    data:
        '''<!doctype html><html><head><meta charset="utf-8"><title>Codex Desk 浏览器</title><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#171717;color:#d6d6d6;display:grid;place-items:center;height:100vh;margin:0}main{text-align:center;max-width:400px}p{color:#989898;line-height:1.6}</style></head><body><main><h1>内置浏览器</h1><p>在上方输入 HTTP 或 HTTPS 地址。网页会在独立的应用浏览器会话中打开。</p></main></body></html>''',
    mimeType: 'text/html',
    encoding: 'utf-8',
  );

  /// 在未注册原生平台（例如 Widget 测试）时显示可测试的降级占位页。
  /// Shows a testable fallback when the native platform is not registered, such as in widget tests.
  Widget buildWebView() {
    if (InAppWebViewPlatform.instance == null) {
      return const Center(child: Text('macOS 内置浏览器仅可在桌面应用中使用。'));
    }
    return InAppWebView(
      key: const Key('browser-native-webview'),
      initialData: initialPage(),
      initialSettings: InAppWebViewSettings(
        isInspectable: kDebugMode,
        mediaPlaybackRequiresUserGesture: true,
      ),
      onWebViewCreated: (controller) {
        _webView = controller;
        unawaited(refreshNavigationState());
      },
      onLoadStart: (controller, url) {
        if (!mounted) return;
        setState(() => _loading = true);
        updateUrl(url);
      },
      onLoadStop: (controller, url) {
        if (!mounted) return;
        setState(() => _loading = false);
        updateUrl(url);
      },
      onUpdateVisitedHistory: (controller, url, isReload) => updateUrl(url),
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true) return;
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = error.description;
        });
        unawaited(refreshNavigationState());
      },
      shouldOverrideUrlLoading: decideNavigation,
    );
  }

  /// 构建浏览器页面并让 WebView 生命周期跟随该页面的挂载状态。
  /// Builds the browser page so the WebView lifecycle follows this page's mount state.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Padding(
      key: const Key('browser-workspace-page'),
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('浏览器', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            '实验性 macOS 内置浏览器。浏览数据和链接打开偏好将在后续阶段提供。',
            style: TextStyle(color: palette.muted),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              IconButton(
                key: const Key('browser-go-back'),
                tooltip: '后退',
                onPressed: _canGoBack ? () => unawaited(goBack()) : null,
                icon: const Icon(Icons.arrow_back),
              ),
              IconButton(
                key: const Key('browser-go-forward'),
                tooltip: '前进',
                onPressed: _canGoForward ? () => unawaited(goForward()) : null,
                icon: const Icon(Icons.arrow_forward),
              ),
              IconButton(
                key: const Key('browser-reload-or-stop'),
                tooltip: _loading ? '停止加载' : '刷新',
                onPressed: () => unawaited(reloadOrStop()),
                icon: Icon(_loading ? Icons.close : Icons.refresh),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('browser-address'),
                  controller: _address,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => unawaited(navigateFromAddress()),
                  decoration: const InputDecoration(
                    hintText: '输入网址，例如 https://example.com',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('browser-open-external'),
                tooltip: '在默认浏览器中打开',
                onPressed: () => unawaited(openInDefaultBrowser()),
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 10),
            Text(error, style: TextStyle(color: palette.fault)),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: palette.border),
                  color: palette.bench,
                ),
                child: Stack(
                  children: [
                    buildWebView(),
                    if (_loading)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
