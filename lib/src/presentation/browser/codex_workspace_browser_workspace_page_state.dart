import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_error_policy.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_download.dart';
import 'package:chatgpt/src/presentation/browser/browser_download_cancellation.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_url_normalizer.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_history_dialog.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_clear_data_dialog.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_download_records_dialog.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/services/browser_history_store.dart';
import 'package:chatgpt/src/domain/browser_tab_snapshot.dart';
import 'package:chatgpt/src/services/browser_download_store.dart';
import 'package:chatgpt/src/services/browser_session_store.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

/// 管理 Codex 风格浏览器标签、原生控制器、导航状态和短生命周期反馈。
/// Owns Codex-style browser tabs, native controllers, navigation state, and transient feedback.
class BrowserWorkspacePageState extends State<BrowserWorkspacePage> {
  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode(debugLabel: 'browser-address');
  final List<int> _tabs = <int>[0];
  final Map<int, InAppWebViewController> _webViews = {};
  final Map<int, int> _popupWindowIds = {};
  final Set<int> _discardedPopupWindowIds = {};
  final Set<int> _invalidatedTabs = {};
  final Set<int> _restoredTabLoadStarted = {};
  final Map<int, String> _urls = {};
  final Map<int, String> _titles = {};
  final Map<int, bool> _loading = {};
  final Map<int, bool> _canGoBack = {};
  final Map<int, bool> _canGoForward = {};
  final Map<int, String> _errors = {};
  final Map<int, String> _loadingUrls = {};
  final Map<int, int> _navigationRequestGenerations = {};
  final Map<int, int> _downloadOperations = {};
  final Map<int, BrowserDownloadCancellation> _downloadCancellations = {};
  final Set<String> _activeDownloadKeys = {};
  int _activeTab = 0;
  int _nextTab = 1;
  int _nextNavigationRequestGeneration = 0;
  int _nextDownloadOperation = 0;
  Timer? _downloadMessageTimer;
  String? _requestedInitialUrl;
  bool _showImportBanner = true;
  String? _downloadMessage;
  late BrowserHistoryStore _historyStore;
  late BrowserDownloadStore _downloadStore;
  late BrowserSessionStore _sessionStore;
  bool _sessionRestoreCompleted = false;
  Future<void> _sessionSaveQueue = Future<void>.value();

  bool get _activeLoading => _loading[_activeTab] ?? false;

  Future<void> _restoreSession() async {
    final saved = await _sessionStore.read();
    if (!mounted ||
        !widget.restoreTabs ||
        (widget.initialUrl?.trim().isNotEmpty ?? false) ||
        _urls.isNotEmpty) {
      _sessionRestoreCompleted = true;
      return;
    }
    if (saved != null) {
      final safeTabs = <BrowserTabSnapshot>[];
      var restoredActiveIndex = 0;
      for (var index = 0; index < saved.tabs.length; index++) {
        final tab = saved.tabs[index];
        final uri = normalizeBrowserUrl(tab.url);
        if (uri != null && await widget.urlSafetyChecker(uri)) {
          if (index == saved.activeIndex) {
            restoredActiveIndex = safeTabs.length;
          }
          safeTabs.add(
            BrowserTabSnapshot(
              url: uri.replace(userInfo: '').toString(),
              title: tab.title,
            ),
          );
        }
      }
      if (mounted && safeTabs.isNotEmpty && !(_requestedInitialUrl != null)) {
        setState(() {
          _tabs
            ..clear()
            ..addAll(List<int>.generate(safeTabs.length, (index) => index));
          _nextTab = safeTabs.length;
          _activeTab = restoredActiveIndex.clamp(0, safeTabs.length - 1);
          _urls
            ..clear()
            ..addEntries(
              safeTabs.asMap().entries.map(
                (entry) => MapEntry(entry.key, entry.value.url),
              ),
            );
          _titles
            ..clear()
            ..addEntries(
              safeTabs.asMap().entries.map(
                (entry) => MapEntry(entry.key, entry.value.title),
              ),
            );
          _setAddress(_urls[_activeTab] ?? '');
        });
      }
    }
    _sessionRestoreCompleted = true;
    if (mounted && widget.initialUrl?.trim().isNotEmpty != true) {
      final tabIds = widget.restoreTabNavigation != null
          ? _tabs.toList(growable: false)
          : _webViews.keys.toList(growable: false);
      for (final tabId in tabIds) {
        unawaited(_loadRestoredTabIfReady(tabId));
      }
    }
    if (mounted && widget.initialUrl != null) {
      unawaited(_loadInitialUrlIfReady());
    }
  }

  void _persistSession() {
    if (!widget.restoreTabs || !_sessionRestoreCompleted) return;
    final tabs = <BrowserTabSnapshot>[];
    var activeIndex = 0;
    for (final tabId in _tabs) {
      final url = normalizeBrowserUrl(_urls[tabId] ?? '');
      if (url == null) continue;
      if (tabId == _activeTab) activeIndex = tabs.length;
      tabs.add(
        BrowserTabSnapshot(
          url: url.replace(userInfo: '').toString(),
          title: _titles[tabId] ?? '新标签页',
        ),
      );
    }
    if (tabs.isEmpty) activeIndex = 0;
    _sessionSaveQueue = _sessionSaveQueue
        .catchError((_) {})
        .then((_) => _sessionStore.save(tabs: tabs, activeIndex: activeIndex));
  }

  @override
  void initState() {
    super.initState();
    _historyStore = widget.historyStore ?? BrowserHistoryStore();
    _downloadStore = widget.downloadStore ?? BrowserDownloadStore();
    _sessionStore = widget.sessionStore ?? BrowserSessionStore();
    if (widget.restoreTabs) unawaited(_restoreSession());
    if (!widget.restoreTabs) _sessionRestoreCompleted = true;
  }

  @override
  void didUpdateWidget(covariant BrowserWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.restoreTabs && widget.restoreTabs) {
      _sessionRestoreCompleted = false;
      unawaited(_restoreSession());
    }
    if (oldWidget.isVisible && !widget.isVisible) {
      _addressFocus.unfocus();
    }
    if (widget.initialUrl != oldWidget.initialUrl ||
        widget.navigationRevision != oldWidget.navigationRevision) {
      _requestedInitialUrl = null;
      unawaited(_loadInitialUrlIfReady());
    }
  }

  @override
  void dispose() {
    for (final cancellation in _downloadCancellations.values) {
      cancellation.cancel();
    }
    _downloadCancellations.clear();
    _persistSession();
    _downloadMessageTimer?.cancel();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  Future<void> navigateFromAddress() async {
    final uri = browserLocationForInput(_address.text);
    if (uri == null) {
      _setError(_activeTab, '请输入有效的网址或搜索内容。');
      return;
    }
    await _navigateTab(_activeTab, uri);
  }

  Future<void> _navigateTab(int tabId, Uri uri) async {
    final requestGeneration = _beginNavigationRequest(tabId);
    final controller = _webViews[tabId];
    if (controller == null) {
      _setError(tabId, '浏览器尚未准备好，请稍后重试。');
      return;
    }
    final safe = await widget.urlSafetyChecker(uri);
    if (!_isCurrentNavigationRequest(tabId, requestGeneration, controller)) {
      return;
    }
    if (!safe) {
      _setError(tabId, '已阻止无法确认安全性的地址。');
      return;
    }
    setState(() => _errors.remove(tabId));
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    } catch (error) {
      if (_isCurrentNavigationRequest(tabId, requestGeneration, controller)) {
        _setError(tabId, '无法加载此地址：$error');
      }
    }
  }

  Future<void> _loadInitialUrlIfReady() async {
    final revision = widget.navigationRevision;
    final tabId = _activeTab;
    final value = widget.initialUrl?.trim();
    if (value == null || value.isEmpty || value == _requestedInitialUrl) return;
    final requestGeneration = _beginNavigationRequest(tabId);
    final uri = normalizeBrowserUrl(value);
    final safe = uri != null && await widget.urlSafetyChecker(uri);
    if (!mounted ||
        revision != widget.navigationRevision ||
        !_tabs.contains(tabId) ||
        _navigationRequestGenerations[tabId] != requestGeneration) {
      return;
    }
    if (!safe) {
      _setError(tabId, '已阻止无法确认安全性的地址。');
      return;
    }
    final controller = _webViews[tabId];
    if (controller == null) return;
    if (!_isCurrentNavigationRequest(tabId, requestGeneration, controller)) {
      return;
    }
    _requestedInitialUrl = value;
    if (tabId == _activeTab) _setAddress(uri.toString());
    setState(() => _errors.remove(tabId));
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    } catch (error) {
      if (_isCurrentNavigationRequest(tabId, requestGeneration, controller)) {
        _setError(tabId, '无法加载此地址：$error');
      }
    }
  }

  Future<void> _loadRestoredTabIfReady(int tabId) async {
    if (!mounted ||
        widget.initialUrl?.trim().isNotEmpty == true ||
        !_sessionRestoreCompleted ||
        !_tabs.contains(tabId) ||
        (_webViews[tabId] == null && widget.restoreTabNavigation == null) ||
        !_restoredTabLoadStarted.add(tabId)) {
      return;
    }
    final value = _urls[tabId];
    final uri = value == null ? null : normalizeBrowserUrl(value);
    if (uri == null) return;
    final restoreTabNavigation = widget.restoreTabNavigation;
    if (restoreTabNavigation != null) {
      final requestGeneration = _beginNavigationRequest(tabId);
      final safe = await widget.urlSafetyChecker(uri);
      if (!mounted ||
          !_tabs.contains(tabId) ||
          _navigationRequestGenerations[tabId] != requestGeneration) {
        return;
      }
      if (!safe) {
        _setError(tabId, '已阻止无法确认安全性的地址。');
        return;
      }
      try {
        await restoreTabNavigation(tabId, uri);
      } catch (error) {
        if (mounted && _tabs.contains(tabId)) {
          _setError(tabId, '无法恢复此标签页：$error');
        }
      }
      return;
    }
    await _navigateTab(tabId, uri);
  }

  void _setError(int tabId, String message) {
    if (!mounted || !_tabs.contains(tabId)) return;
    setState(() => _errors[tabId] = message);
  }

  int _beginNavigationRequest(int tabId) {
    final generation = ++_nextNavigationRequestGeneration;
    _navigationRequestGenerations[tabId] = generation;
    return generation;
  }

  bool _isCurrentNavigationRequest(
    int tabId,
    int generation,
    InAppWebViewController controller,
  ) =>
      mounted &&
      _tabs.contains(tabId) &&
      _navigationRequestGenerations[tabId] == generation &&
      identical(controller, _webViews[tabId]);

  bool _isCurrentWebView(int tabId, InAppWebViewController? controller) =>
      mounted &&
      _tabs.contains(tabId) &&
      !_invalidatedTabs.contains(tabId) &&
      (controller == null || identical(controller, _webViews[tabId]));

  void _setAddress(String value) {
    _address.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _focusAddress() {
    _addressFocus.requestFocus();
    _address.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _address.text.length,
    );
  }

  void _newTab() {
    final tabId = _nextTab++;
    setState(() {
      _tabs.add(tabId);
      _activeTab = tabId;
      _address.clear();
    });
    _persistSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeTab != tabId || !_tabs.contains(tabId)) return;
      _focusAddress();
    });
  }

  void _selectTab(int tabId) {
    if (tabId == _activeTab) return;
    setState(() {
      _activeTab = tabId;
      _setAddress(_urls[tabId] ?? '');
    });
    _persistSession();
  }

  void _closeTab(int tabId) {
    final index = _tabs.indexOf(tabId);
    if (index < 0) return;
    _invalidateTab(tabId);
    if (_tabs.length == 1) {
      if (widget.restoreTabs) unawaited(_sessionStore.clear());
      widget.onOpenConversation();
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      _webViews.remove(tabId);
      _popupWindowIds.remove(tabId);
      _urls.remove(tabId);
      _titles.remove(tabId);
      _loading.remove(tabId);
      _loadingUrls.remove(tabId);
      _canGoBack.remove(tabId);
      _canGoForward.remove(tabId);
      _errors.remove(tabId);
      if (_activeTab == tabId) {
        _activeTab = _tabs[index.clamp(0, _tabs.length - 1)];
        _setAddress(_urls[_activeTab] ?? '');
      }
    });
    _persistSession();
  }

  /// Invalidates every asynchronous callback that belongs to a tab before it
  /// is removed from the workspace. The WebView plugin may still deliver
  /// navigation, title, history, error, or download callbacks after close.
  void _invalidateTab(int tabId) {
    _invalidatedTabs.add(tabId);
    _navigationRequestGenerations[tabId] = ++_nextNavigationRequestGeneration;
    _downloadCancellations.remove(tabId)?.cancel();
    _downloadOperations.remove(tabId);
    _restoredTabLoadStarted.remove(tabId);
  }

  Future<void> openInDefaultBrowser() async {
    final tabId = _activeTab;
    final uri = normalizeBrowserUrl(_urls[tabId] ?? _address.text);
    if (uri == null || !await widget.urlSafetyChecker(uri)) {
      _setError(tabId, '当前标签页没有可在默认浏览器中打开的地址。');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _setError(tabId, '无法在系统默认浏览器中打开此地址。');
    } catch (error) {
      _setError(tabId, '无法在系统默认浏览器中打开此地址：$error');
    }
  }

  Future<void> handleDownloadStart(
    int tabId,
    DownloadStartRequest request,
    InAppWebViewController? controller,
  ) async {
    if (!_isCurrentWebView(tabId, controller)) return;
    final downloadKey =
        '$tabId:${request.url}:${request.suggestedFilename ?? ''}';
    if (!_activeDownloadKeys.add(downloadKey)) return;
    try {
      await _handleDownloadStartOnce(tabId, request, controller);
    } finally {
      _activeDownloadKeys.remove(downloadKey);
    }
  }

  Future<void> _handleDownloadStartOnce(
    int tabId,
    DownloadStartRequest request,
    InAppWebViewController? controller,
  ) async {
    if (!_isCurrentWebView(tabId, controller)) return;
    final source = Uri.tryParse(request.url.toString());
    if (source == null || !await widget.urlSafetyChecker(source)) {
      if (!mounted || !_isCurrentWebView(tabId, controller)) return;
      _showDownloadMessage('已阻止不安全的下载地址。');
      return;
    }
    if (!mounted || !_isCurrentWebView(tabId, controller)) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('下载文件？'),
        content: Text(
          '来源：${source.host}\n文件：${browserDownloadSuggestedFilename(request.suggestedFilename)}\n\n下载前仍需选择保存位置。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (!_isCurrentWebView(tabId, controller) || approved != true) return;
    final operation = ++_nextDownloadOperation;
    _downloadOperations[tabId] = operation;
    final cancellation = BrowserDownloadCancellation();
    _downloadCancellations[tabId] = cancellation;
    _showDownloadMessage('正在等待选择下载位置…');
    try {
      final saveDownload = widget.downloadSaver ?? saveBrowserDownload;
      final savedPath = await saveDownload(
        request: request,
        urlSafetyChecker: widget.urlSafetyChecker,
        downloadDirectory: widget.downloadDirectory,
        askForLocation: widget.askBeforeDownload,
        cancellation: cancellation,
        pickLocation: (suggestedName) => getSaveLocation(
          suggestedName: suggestedName,
          confirmButtonText: '保存',
          canCreateDirectories: false,
        ),
      );
      if (!_isCurrentWebView(tabId, controller) ||
          _downloadOperations[tabId] != operation) {
        return;
      }
      if (savedPath != null && !cancellation.isCancelled) {
        try {
          await _downloadStore.record(url: source, filePath: savedPath);
        } catch (error) {
          _showDownloadMessage('下载已保存，但记录失败：$error');
          return;
        }
      }
      _showDownloadMessage(
        savedPath == null || cancellation.isCancelled
            ? '已取消下载。'
            : '下载已保存：$savedPath',
      );
    } catch (error) {
      if (!_isCurrentWebView(tabId, controller) ||
          _downloadOperations[tabId] != operation) {
        return;
      }
      _showDownloadMessage(cancellation.isCancelled ? '已取消下载。' : '下载失败：$error');
    } finally {
      if (identical(_downloadCancellations[tabId], cancellation)) {
        _downloadCancellations.remove(tabId);
      }
    }
  }

  void cancelActiveDownload() {
    if (_downloadCancellations.isEmpty) return;
    final tabId = _downloadCancellations.keys.first;
    _downloadCancellations[tabId]?.cancel();
    _showDownloadMessage('正在取消下载…');
  }

  void _showDownloadMessage(String message) {
    if (!mounted) return;
    _downloadMessageTimer?.cancel();
    setState(() => _downloadMessage = message);
    _downloadMessageTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _downloadMessage = null);
    });
  }

  Future<void> goBack() async {
    final tabId = _activeTab;
    final controller = _webViews[tabId];
    if (controller == null || !await controller.canGoBack()) return;
    try {
      await controller.goBack();
      await refreshNavigationState(tabId);
    } catch (error) {
      _setError(tabId, '后退失败：$error');
    }
  }

  Future<void> goForward() async {
    final tabId = _activeTab;
    final controller = _webViews[tabId];
    if (controller == null || !await controller.canGoForward()) return;
    try {
      await controller.goForward();
      await refreshNavigationState(tabId);
    } catch (error) {
      _setError(tabId, '前进失败：$error');
    }
  }

  Future<void> reloadOrStop() async {
    final tabId = _activeTab;
    final controller = _webViews[tabId];
    if (controller == null) return;
    try {
      if (_loading[tabId] ?? false) {
        await controller.stopLoading();
      } else if (_urls.containsKey(tabId)) {
        await controller.reload();
      }
    } catch (error) {
      _setError(tabId, '${_activeLoading ? '停止加载' : '刷新'}失败：$error');
    }
  }

  Future<void> refreshNavigationState(int tabId) async {
    final controller = _webViews[tabId];
    if (controller == null) return;
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (!mounted || !identical(controller, _webViews[tabId])) return;
      setState(() {
        _canGoBack[tabId] = back;
        _canGoForward[tabId] = forward;
      });
    } catch (_) {}
  }

  void updateUrl(int tabId, WebUri? url, {InAppWebViewController? controller}) {
    if (url == null || !_isCurrentWebView(tabId, controller)) return;
    if (url.scheme == 'about' || url.scheme == 'data') return;
    if (!isBrowserWebUri(url)) {
      _setError(tabId, '已阻止指向本机或私有网络的地址。');
      return;
    }
    final value = url.toString();
    setState(() {
      _urls[tabId] = value;
      _errors.remove(tabId);
      if (tabId == _activeTab) _setAddress(value);
    });
    unawaited(refreshNavigationState(tabId));
  }

  Future<NavigationActionPolicy?> decideNavigation(
    int tabId,
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url;
    if (url == null) return NavigationActionPolicy.CANCEL;
    if (url.scheme == 'about' || url.scheme == 'data') {
      return NavigationActionPolicy.ALLOW;
    }
    if (await widget.urlSafetyChecker(url)) {
      if (!_isCurrentWebView(tabId, controller)) {
        return NavigationActionPolicy.CANCEL;
      }
      handleNavigationAuthorized(tabId, url, controller: controller);
      return NavigationActionPolicy.ALLOW;
    }
    if (url.scheme == 'http' || url.scheme == 'https') {
      _setError(tabId, '已阻止指向本机或私有网络的地址。');
      return NavigationActionPolicy.CANCEL;
    }
    try {
      final opened = await launchUrl(
        Uri.parse(url.toString()),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _setError(tabId, '此地址无法在系统默认应用中打开。');
    } catch (error) {
      _setError(tabId, '此地址无法在系统默认应用中打开：$error');
    }
    return NavigationActionPolicy.CANCEL;
  }

  Future<bool> handleCreateWindow(
    int sourceTabId,
    CreateWindowAction action,
  ) async {
    final url = action.request.url;
    var shouldDiscard = false;
    if (url != null && url.scheme != 'about' && url.scheme != 'data') {
      if (!isBrowserWebUri(url) || !await widget.urlSafetyChecker(url)) {
        shouldDiscard = true;
      }
    }
    if (!mounted) return true;
    if (_popupWindowIds.containsValue(action.windowId)) return true;
    if (shouldDiscard || !_tabs.contains(sourceTabId)) {
      setState(() {
        if (shouldDiscard && _tabs.contains(sourceTabId)) {
          _errors[sourceTabId] = '已阻止指向本机或私有网络的新窗口。';
        }
        _discardedPopupWindowIds.add(action.windowId);
      });
      return true;
    }

    final tabId = _nextTab++;
    setState(() {
      _tabs.add(tabId);
      _activeTab = tabId;
      _popupWindowIds[tabId] = action.windowId;
      if (url != null && isBrowserWebUri(url)) {
        final value = url.toString();
        _urls[tabId] = value;
        _setAddress(value);
      } else {
        _address.clear();
      }
    });
    _persistSession();
    return true;
  }

  void handleCloseWindow(int tabId) {
    if (!_popupWindowIds.containsKey(tabId)) return;
    _closeTab(tabId);
  }

  bool _matchesLoadingUrl(int tabId, WebUri? url) {
    final loadingUrl = _loadingUrls[tabId];
    return loadingUrl != null && url != null && loadingUrl == url.toString();
  }

  void handleNavigationAuthorized(
    int tabId,
    WebUri url, {
    InAppWebViewController? controller,
  }) {
    if (!_isCurrentWebView(tabId, controller)) return;
    _loadingUrls[tabId] = url.toString();
  }

  void handleNavigationStarted(
    int tabId,
    WebUri? url, {
    InAppWebViewController? controller,
  }) {
    if (!_isCurrentWebView(tabId, controller)) {
      return;
    }
    final authorizedUrl = _loadingUrls[tabId];
    if (authorizedUrl != null &&
        url != null &&
        authorizedUrl != url.toString()) {
      return;
    }
    setState(() {
      _loading[tabId] = true;
      if (url != null) _loadingUrls[tabId] = url.toString();
    });
    updateUrl(tabId, url, controller: controller);
  }

  void handleNavigationStopped(
    int tabId,
    WebUri? url, {
    InAppWebViewController? controller,
  }) {
    if (!_isCurrentWebView(tabId, controller) ||
        !_matchesLoadingUrl(tabId, url)) {
      return;
    }
    setState(() {
      _loading[tabId] = false;
      _loadingUrls.remove(tabId);
    });
    updateUrl(tabId, url, controller: controller);
    if (url != null) {
      unawaited(_recordHistory(url, _titles[tabId]));
      _persistSession();
    }
  }

  void handleTitleChanged(
    int tabId,
    String? title, {
    InAppWebViewController? controller,
  }) {
    if (!_isCurrentWebView(tabId, controller)) return;
    final nextTitle = title?.trim();
    setState(() {
      _titles[tabId] = nextTitle?.isNotEmpty == true ? nextTitle! : '新标签页';
    });
    _persistSession();
  }

  void handleVisitedHistoryUpdate(
    int tabId,
    WebUri? url, {
    InAppWebViewController? controller,
  }) {
    if (!_isCurrentWebView(tabId, controller)) return;
    updateUrl(tabId, url, controller: controller);
    if (url != null) {
      unawaited(_recordHistory(url, _titles[tabId]));
      _persistSession();
    }
  }

  Future<void> _recordHistory(WebUri url, String? title) =>
      _historyStore.record(uri: Uri.parse(url.toString()), title: title);

  Future<void> showBrowserHistory() async {
    final entries = await _historyStore.read();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => BrowserHistoryDialog(
        entries: entries,
        store: _historyStore,
        onOpen: (uri) => unawaited(_navigateTab(_activeTab, uri)),
      ),
    );
  }

  Future<void> clearBrowsingData() async {
    if (!mounted) return;
    final selection = await showDialog<Set<String>>(
      context: context,
      builder: (context) => const BrowserClearDataDialog(),
    );
    if (selection == null || selection.isEmpty || !mounted) return;
    final failures = <String>[];
    if (selection.contains('website')) {
      try {
        final clearWebsiteData = widget.clearWebsiteData;
        if (clearWebsiteData != null) {
          await clearWebsiteData();
        } else {
          await CookieManager.instance().deleteAllCookies();
          await WebStorageManager.instance().deleteAllData();
        }
      } catch (error) {
        failures.add('Cookie/网站存储：$error');
      }
    }
    if (selection.contains('cache')) {
      try {
        final clearCache = widget.clearCache;
        if (clearCache != null) {
          await clearCache();
        } else {
          await InAppWebViewController.clearAllCache();
        }
      } catch (error) {
        failures.add('缓存：$error');
      }
    }
    if (selection.contains('history')) {
      try {
        final clearNavigationHistory = widget.clearNavigationHistory;
        if (clearNavigationHistory != null) {
          await clearNavigationHistory();
        } else {
          for (final controller in _webViews.values) {
            await controller.clearHistory();
          }
        }
        await _historyStore.clear();
      } catch (error) {
        failures.add('历史：$error');
      }
    }
    if (selection.contains('downloads')) {
      try {
        await _downloadStore.clear();
      } catch (error) {
        failures.add('下载记录：$error');
      }
    }
    if (failures.isEmpty) {
      _showDownloadMessage('已清除所选浏览数据（下载文件未删除）。');
    } else {
      _showDownloadMessage('部分浏览数据清除失败：${failures.join('；')}');
    }
  }

  Future<void> showDownloadRecords() async {
    final records = await _downloadStore.read();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) =>
          BrowserDownloadRecordsDialog(records: records, store: _downloadStore),
    );
  }

  void handleNavigationError(
    int tabId,
    WebResourceRequest request,
    WebResourceError error, {
    InAppWebViewController? controller,
  }) {
    if (request.isForMainFrame != true ||
        !_isCurrentWebView(tabId, controller) ||
        !_matchesLoadingUrl(tabId, request.url)) {
      return;
    }
    setState(() {
      _loading[tabId] = false;
      _loadingUrls.remove(tabId);
    });
    if (shouldReportBrowserWebResourceError(error)) {
      _setError(tabId, error.description);
    }
    unawaited(refreshNavigationState(tabId));
  }

  Widget _buildDiscardedPopupWindow(int windowId) {
    if (InAppWebViewPlatform.instance == null) {
      return const SizedBox.shrink();
    }
    return Offstage(
      child: SizedBox.square(
        dimension: 1,
        child: InAppWebView(
          key: ValueKey('browser-discarded-popup-$windowId'),
          windowId: windowId,
          onWebViewCreated: (controller) {
            unawaited(_finishDiscardingPopup(windowId, controller));
          },
        ),
      ),
    );
  }

  Future<void> _finishDiscardingPopup(
    int windowId,
    InAppWebViewController controller,
  ) async {
    try {
      await controller.stopLoading();
    } catch (_) {}
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_discardedPopupWindowIds.remove(windowId)) return;
      setState(() {});
    });
  }

  InAppWebViewInitialData initialPage() => InAppWebViewInitialData(
    data:
        '<!doctype html><html><head><meta charset="utf-8"><title>新标签页</title></head><body></body></html>',
    mimeType: 'text/html',
    encoding: 'utf-8',
  );

  Widget buildWebView(int tabId) {
    if (InAppWebViewPlatform.instance == null) {
      return const SizedBox.expand();
    }
    return InAppWebView(
      key: ValueKey('browser-native-webview-$tabId'),
      windowId: _popupWindowIds[tabId],
      initialData: _popupWindowIds.containsKey(tabId) ? null : initialPage(),
      initialSettings: InAppWebViewSettings(
        isInspectable: kDebugMode,
        mediaPlaybackRequiresUserGesture: true,
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
        useOnDownloadStart: true,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (controller) {
        if (!mounted || !_tabs.contains(tabId)) return;
        _webViews[tabId] = controller;
        unawaited(refreshNavigationState(tabId));
        if (widget.initialUrl?.trim().isNotEmpty == true) {
          if (tabId == _activeTab) unawaited(_loadInitialUrlIfReady());
        } else {
          unawaited(_loadRestoredTabIfReady(tabId));
        }
      },
      onLoadStart: (controller, url) {
        if (!mounted || !_tabs.contains(tabId)) return;
        if (url != null &&
            url.scheme != 'about' &&
            url.scheme != 'data' &&
            !isBrowserWebUri(url)) {
          unawaited(controller.stopLoading());
          setState(() {
            _loading[tabId] = false;
            _loadingUrls.remove(tabId);
          });
          _setError(tabId, '已阻止指向本机或私有网络的地址。');
          return;
        }
        handleNavigationStarted(tabId, url, controller: controller);
      },
      onLoadStop: (controller, url) =>
          handleNavigationStopped(tabId, url, controller: controller),
      onTitleChanged: (controller, title) {
        handleTitleChanged(tabId, title, controller: controller);
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        handleVisitedHistoryUpdate(tabId, url, controller: controller);
      },
      onReceivedError: (controller, request, error) =>
          handleNavigationError(tabId, request, error, controller: controller),
      onPermissionRequest: (controller, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onDownloadStartRequest: (controller, request) =>
          unawaited(handleDownloadStart(tabId, request, controller)),
      onCreateWindow: (controller, action) async {
        return handleCreateWindow(tabId, action);
      },
      onCloseWindow: (controller) => handleCloseWindow(tabId),
      shouldOverrideUrlLoading: (controller, action) =>
          decideNavigation(tabId, controller, action),
    );
  }

  Widget _iconButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: tooltip,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    ),
  );

  Widget _buildTabStrip(YeknomPalette palette) => SizedBox(
    height: 38,
    child: Row(
      children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 8, top: 5),
            itemCount: _tabs.length,
            itemBuilder: (context, index) {
              final tabId = _tabs[index];
              final selected = tabId == _activeTab;
              final title = _titles[tabId] ?? '新标签页';
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Semantics(
                  container: true,
                  button: true,
                  selected: selected,
                  label: '标签页：$title',
                  hint: selected ? '当前标签页' : '切换到此标签页',
                  child: Material(
                    color: selected ? palette.field : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    child: InkWell(
                      key: ValueKey('browser-tab-$tabId'),
                      onTap: () => _selectTab(tabId),
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        width: 156,
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            Icon(
                              Icons.language,
                              size: 13,
                              color: palette.muted,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.trace,
                                ),
                              ),
                            ),
                            IconButton(
                              key: ValueKey('browser-close-tab-$tabId'),
                              tooltip: '关闭标签页 (⌘W)',
                              onPressed: () => _closeTab(tabId),
                              icon: const Icon(Icons.close, size: 13),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                            ),
                            const SizedBox(width: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _iconButton(
          key: const Key('browser-new-tab'),
          tooltip: '新建标签页 (⌘T)',
          icon: Icons.add,
          onPressed: _newTab,
        ),
        const SizedBox(width: 8),
      ],
    ),
  );

  Widget _buildToolbar(YeknomPalette palette) => SizedBox(
    height: 42,
    child: Row(
      children: [
        const SizedBox(width: 8),
        _iconButton(
          key: const Key('browser-go-back'),
          tooltip: '后退',
          icon: Icons.arrow_back,
          onPressed: (_canGoBack[_activeTab] ?? false)
              ? () => unawaited(goBack())
              : null,
        ),
        _iconButton(
          key: const Key('browser-go-forward'),
          tooltip: '前进',
          icon: Icons.arrow_forward,
          onPressed: (_canGoForward[_activeTab] ?? false)
              ? () => unawaited(goForward())
              : null,
        ),
        _iconButton(
          key: const Key('browser-reload-or-stop'),
          tooltip: _activeLoading ? '停止加载' : '刷新 (⌘R)',
          icon: _activeLoading ? Icons.close : Icons.refresh,
          onPressed: _urls.containsKey(_activeTab)
              ? () => unawaited(reloadOrStop())
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            textField: true,
            label: '地址栏',
            hint: '搜索或输入网址',
            child: SizedBox(
              height: 30,
              child: TextField(
                key: const Key('browser-address'),
                focusNode: _addressFocus,
                controller: _address,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => unawaited(navigateFromAddress()),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: '搜索或输入网址',
                  hintStyle: TextStyle(color: palette.faint),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  filled: true,
                  fillColor: palette.field,
                  prefixIcon: _urls.containsKey(_activeTab)
                      ? Icon(Icons.lock_outline, size: 13, color: palette.muted)
                      : null,
                  prefixIconConstraints: const BoxConstraints(minWidth: 31),
                  suffixIcon: _activeLoading
                      ? const Padding(
                          padding: EdgeInsets.all(7),
                          child: SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _iconButton(
          key: const Key('browser-open-external'),
          tooltip: '在默认浏览器中打开',
          icon: Icons.open_in_new,
          onPressed: _urls.containsKey(_activeTab)
              ? () => unawaited(openInDefaultBrowser())
              : null,
        ),
        PopupMenuButton<String>(
          key: const Key('browser-more-menu'),
          tooltip: '更多',
          icon: const Icon(Icons.more_vert, size: 16),
          padding: EdgeInsets.zero,
          onSelected: (value) {
            if (value == 'new') _newTab();
            if (value == 'external') unawaited(openInDefaultBrowser());
            if (value == 'close') _closeTab(_activeTab);
            if (value == 'history') unawaited(showBrowserHistory());
            if (value == 'clear-data') unawaited(clearBrowsingData());
            if (value == 'downloads') unawaited(showDownloadRecords());
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'new', child: Text('新建标签页    ⌘T')),
            if (_urls.containsKey(_activeTab))
              const PopupMenuItem(value: 'external', child: Text('在默认浏览器中打开')),
            const PopupMenuItem(value: 'history', child: Text('浏览历史')),
            const PopupMenuItem(value: 'downloads', child: Text('下载记录')),
            const PopupMenuItem(value: 'clear-data', child: Text('清除浏览数据')),
            const PopupMenuItem(value: 'close', child: Text('关闭标签页    ⌘W')),
          ],
        ),
        const SizedBox(width: 4),
      ],
    ),
  );

  Widget _buildImportBanner(YeknomPalette palette) => Container(
    key: const Key('browser-import-banner'),
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: palette.bench,
      border: Border(bottom: BorderSide(color: palette.border)),
    ),
    child: Row(
      children: [
        Container(
          width: 19,
          height: 19,
          decoration: const BoxDecoration(
            color: Color(0xFF4285F4),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.circle, size: 7, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '从 Chrome 导入数据',
                style: TextStyle(fontSize: 12, color: palette.trace),
              ),
              Text(
                '将你的密码和 Cookie 导入内置浏览器',
                style: TextStyle(fontSize: 10, color: palette.muted),
              ),
            ],
          ),
        ),
        TextButton(
          key: const Key('browser-import-chrome'),
          onPressed: _showChromeImportBoundary,
          child: const Text('导入'),
        ),
        _iconButton(
          key: const Key('browser-dismiss-import'),
          tooltip: '关闭',
          icon: Icons.close,
          onPressed: () => setState(() => _showImportBanner = false),
        ),
      ],
    ),
  );

  Widget _buildDownloadBanner(YeknomPalette palette) {
    final message = _downloadMessage;
    if (message == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      liveRegion: true,
      label: '下载状态：$message',
      child: Container(
        key: const Key('browser-download-banner'),
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: palette.raised,
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Icon(Icons.download_done_outlined, size: 16, color: palette.signal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 11, color: palette.trace),
              ),
            ),
            IconButton(
              key: _downloadCancellations.isNotEmpty
                  ? const Key('browser-cancel-download')
                  : null,
              tooltip: '取消下载',
              onPressed: _downloadCancellations.isEmpty
                  ? null
                  : cancelActiveDownload,
              icon: const Icon(Icons.stop_circle_outlined, size: 15),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
            IconButton(
              tooltip: '关闭下载提示',
              onPressed: () => setState(() => _downloadMessage = null),
              icon: const Icon(Icons.close, size: 15),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChromeImportBoundary() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('浏览器数据保持独立'),
      content: const Text('为保护你的登录状态，当前版本不会读取 Chrome 的密码、Cookie、书签或历史记录。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  Widget _buildEmptyState(YeknomPalette palette) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.language, size: 27, color: palette.muted),
        const SizedBox(height: 13),
        Text(
          '开始浏览',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: palette.trace,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '输入 URL 以打开页面',
          style: TextStyle(fontSize: 11, color: palette.muted),
        ),
      ],
    ),
  );

  Widget _buildPageBody(YeknomPalette palette) => Semantics(
    key: const Key('browser-page-body'),
    container: true,
    label: '网页内容',
    child: Stack(
      fit: StackFit.expand,
      children: [
        IndexedStack(
          index: _tabs.indexOf(_activeTab),
          children: [
            for (final tabId in _tabs)
              Stack(
                fit: StackFit.expand,
                children: [
                  buildWebView(tabId),
                  if (!_urls.containsKey(tabId) &&
                      !_popupWindowIds.containsKey(tabId))
                    ColoredBox(
                      color: palette.bench,
                      child: _buildEmptyState(palette),
                    ),
                ],
              ),
          ],
        ),
        for (final windowId in _discardedPopupWindowIds)
          _buildDiscardedPopupWindow(windowId),
        if (_errors[_activeTab] case final error?)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Semantics(
              key: const Key('browser-error-banner'),
              container: true,
              liveRegion: true,
              label: '浏览器错误：$error',
              child: Material(
                color: palette.raised,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: palette.fault),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (_urls.containsKey(_activeTab))
                        TextButton(
                          onPressed: () => unawaited(reloadOrStop()),
                          child: const Text('重试'),
                        ),
                      IconButton(
                        tooltip: '关闭错误提示',
                        onPressed: () =>
                            setState(() => _errors.remove(_activeTab)),
                        icon: const Icon(Icons.close, size: 15),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
            _focusAddress,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true): _newTab,
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
            _closeTab(_activeTab),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () =>
            unawaited(reloadOrStop()),
      },
      child: Focus(
        autofocus: widget.isVisible,
        canRequestFocus: widget.isVisible,
        descendantsAreFocusable: widget.isVisible,
        child: Semantics(
          container: true,
          label: '内置浏览器工作区',
          child: Material(
            key: const Key('browser-workspace-page'),
            color: palette.bench,
            child: Column(
              children: [
                _buildTabStrip(palette),
                Divider(height: 1, color: palette.border),
                _buildToolbar(palette),
                Divider(height: 1, color: palette.border),
                if (_showImportBanner) _buildImportBanner(palette),
                _buildDownloadBanner(palette),
                Expanded(child: _buildPageBody(palette)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
