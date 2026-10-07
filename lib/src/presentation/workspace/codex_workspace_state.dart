import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_page.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart';
import 'package:chatgpt/src/presentation/files/codex_workspace_files_workspace_page.dart';
import 'package:chatgpt/src/presentation/files/workspace_source_file_preview.dart';
import 'package:chatgpt/src/presentation/agents/codex_workspace_agents_page.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_desktop_side_panel.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_codex_configuration_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_account_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_runtime_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_directories_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_edit_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_archived_threads_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_marketplaces_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_rename_thread_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_delete_thread_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/browser_link_open_scope.dart';
import 'package:chatgpt/src/presentation/workspace/workspace_file_open_scope.dart';
import 'package:chatgpt/src/presentation/workspace/workspace_file_tabs_notifier.dart';
import 'package:chatgpt/src/presentation/workspace/workspace_file_tabs_state.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:flutter/scheduler.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';

/// 拥有短生命周期界面状态，并把可共享业务状态交由 [CodexController] 管理。
/// Owns short-lived UI state while delegating shared business state to [CodexController].

class CodexWorkspaceState extends ConsumerState<CodexWorkspace>
    with WidgetsBindingObserver {
  final GlobalKey<SidebarState> _sidebarKey = GlobalKey<SidebarState>();
  final TextEditingController _composer = TextEditingController();
  final Map<ThreadViewportKey, ScrollController> _timelineScrollControllers =
      {};
  final Map<ThreadViewportKey, bool> _timelineFollowsLatest = {};
  final Map<ThreadViewportKey, bool> _timelineIsAboveLatest = {};
  final Map<ThreadViewportKey, bool> _pendingTimelineAboveLatest = {};
  final Map<ThreadViewportKey, double> _timelineViewportDimensions = {};
  final Map<ThreadViewportKey, TimelinePageData> _timelinePages = {};
  final Map<ThreadViewportKey, bool> _fileChangeSummaryExpanded = {};
  final Map<String, bool> _activityListExpanded = {};
  late ScrollController _timelineScrollController;
  late ThreadViewportKey _displayedThreadKey;
  bool _timelineScrollScheduled = false;
  bool _timelineAboveLatestUpdateScheduled = false;
  int _timelineScrollRequestGeneration = 0;
  int _timelineScrollAnimationGeneration = 0;
  ThreadViewportKey? _timelineScrollAnimationViewport;
  ThreadViewportKey? _threadHistoryLoadingKey;
  bool _suppressTimelineScrollAfterThreadResume = false;
  WorkspaceDestination _destination = WorkspaceDestination.conversation;
  int _timelineScrollGeneration = 0;
  static const _minimumSidebarWidth = 210.0;
  static const _maximumSidebarWidth = 420.0;
  static const _minimumInspectorWidth = 220.0;
  static const _maximumInspectorWidth = 360.0;
  static const _minimumReviewWidth = 600.0;
  static const _maximumReviewWidth = 960.0;
  static const _minimumAuxiliaryWidth = 360.0;
  static const _auxiliaryPaneAllowance = 24.0;
  double _sidebarWidth = CodexThemePreferences.defaultSidebarWidth;
  double _inspectorWidth = 240;
  double _reviewWidth = _maximumReviewWidth;
  bool _reviewOpen = false;
  CodeReviewSource _reviewSource = CodeReviewSource.latestTurn;
  final GlobalKey _reviewPanelKey = GlobalKey();
  final GlobalKey<BrowserWorkspacePageState> _browserPanelKey = GlobalKey();
  // Native WebView creation is expensive on macOS. Keep the browser mounted
  // after its first use, but do not construct it during the initial frame.
  // 原生 WebView 在 macOS 上初始化成本较高；首次使用后保活，但首帧不创建。
  bool _browserPageMounted = false;
  bool _filesPageMounted = false;
  late final WorkspaceFileTabsProviderArgument _workspaceFileTabsArgument;
  late ProviderContainer _workspaceFileTabsContainer;
  late ProviderSubscription<WorkspaceFileTabsState>
  _workspaceFileTabsSubscription;
  bool _ownsWorkspaceFileTabsContainer = false;
  String? _browserInitialUrl;
  int _browserNavigationRevision = 0;
  String? _selectedSubagentThreadId;
  String? _selectedSubagentParentThreadId;
  final Set<String> _openedSubagentThreadIds = <String>{};
  final Map<String, String> _subagentTitles = <String, String>{};
  String _activeSidePanelTab = 'review';
  bool _sidePanelCollapsed = true;
  late CodexController _controller;
  double? _settingsReturnTimelineOffset;
  bool _appWasInactive = false;
  bool _appIsForegrounded = true;
  CodexSideChatSession? _sideChatSession;

  Future<void> _openSideChat() async {
    if (_sideChatSession != null) return;
    final session = await _controller.openSideChat();
    if (session == null) return;
    if (!mounted || _reviewOpen || _sideChatSession != null) {
      session.dispose();
      return;
    }
    setState(() {
      _sideChatSession = session;
      _activeSidePanelTab = 'side-chat';
      _sidePanelCollapsed = false;
    });
  }

  void _closeSideChat() {
    final session = _sideChatSession;
    if (session == null) return;
    session.dispose();
    setState(() {
      _sideChatSession = null;
      _activeSidePanelTab = _fallbackSidePanelTab() ?? '';
      if (_activeSidePanelTab.isEmpty) _sidePanelCollapsed = true;
    });
  }

  bool get _threadHistoryLoading =>
      _threadHistoryLoadingKey == _displayedThreadKey;

  double _sidebarMaximumFor(double maxWidth) {
    final compact = maxWidth < 980;
    return (maxWidth - (compact ? 360 : _inspectorWidth + 420))
        .clamp(_minimumSidebarWidth, _maximumSidebarWidth)
        .toDouble();
  }

  double _sidebarWidthFor(double maxWidth) => _sidebarWidth
      .clamp(_minimumSidebarWidth, _sidebarMaximumFor(maxWidth))
      .toDouble();

  /// 注册控制器监听器，使时间线在内容更新后自动滚动。
  /// Registers the controller listener that scrolls the timeline after updates.
  @override
  void initState() {
    super.initState();
    _sidebarWidth = widget.initialSidebarWidth
        .clamp(_minimumSidebarWidth, _maximumSidebarWidth)
        .toDouble();
    _controller = widget.controller ?? ref.read(codexControllerProvider)!;
    _workspaceFileTabsArgument = (
      scope: Object(),
      initialWorkspacePath: _controller.workspacePath,
    );
    try {
      _workspaceFileTabsContainer = ProviderScope.containerOf(
        context,
        listen: false,
      );
    } on StateError {
      _workspaceFileTabsContainer = ProviderContainer();
      _ownsWorkspaceFileTabsContainer = true;
    }
    _workspaceFileTabsSubscription = _workspaceFileTabsContainer.listen(
      workspaceFileTabsProvider(_workspaceFileTabsArgument),
      (previous, next) {
        if (mounted) setState(() {});
      },
    );
    _displayedThreadKey = _viewportKey(_controller.activeThreadId);
    _timelineScrollController = _timelineControllerFor(_displayedThreadKey);
    _captureActiveTimelinePage();
    _controller.addListener(_handleControllerUpdate);
    _controller.setDockActivationHandler(_handleDockActivation);
    _controller.setOpenSettingsHandler(_showSettings);
    _controller.setBrowserInvocationHandler(_handleBrowserInvocation);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _syncUserInputSurfaceState()) setState(() {});
    });
  }

  /// 将嵌入或测试场景替换的控制器同步到监听、动作和时间线缓存。
  /// Synchronizes a replaced embedded/test controller with listeners, actions, and timeline caches.
  @override
  void didUpdateWidget(covariant CodexWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextController =
        widget.controller ?? ref.read(codexControllerProvider)!;
    if (identical(nextController, _controller)) return;
    final previousController = _controller;
    previousController.removeListener(_handleControllerUpdate);
    previousController.setDockActivationHandler(null);
    previousController.setOpenSettingsHandler(null);
    previousController.setBrowserInvocationHandler(null);
    previousController.setUserInputSurfaceState(
      foregrounded: false,
      presentedThreadId: null,
    );
    _controller = nextController;
    final nextWorkspacePath = _controller.workspacePath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller.workspacePath != nextWorkspacePath) return;
      final workspaceChanged = _synchronizeWorkspaceFileTabs(nextWorkspacePath);
      if (!workspaceChanged || !_activeSidePanelTab.startsWith('file:')) {
        return;
      }
      setState(() {
        _activeSidePanelTab = _fallbackSidePanelTab() ?? '';
        if (_activeSidePanelTab.isEmpty) _sidePanelCollapsed = true;
      });
    });
    _controller.addListener(_handleControllerUpdate);
    _controller.setDockActivationHandler(_handleDockActivation);
    _controller.setOpenSettingsHandler(_showSettings);
    _controller.setBrowserInvocationHandler(_handleBrowserInvocation);
    _syncUserInputSurfaceState();
    _selectedSubagentThreadId = null;
    _selectedSubagentParentThreadId = null;
    _timelineScrollGeneration++;
    _timelineScrollAnimationViewport = null;
    _timelineScrollAnimationGeneration++;
    _timelineScrollScheduled = false;
    _threadHistoryLoadingKey = null;
    _displayedThreadKey = _viewportKey(_controller.activeThreadId);
    _timelineScrollController = _timelineControllerFor(_displayedThreadKey);
    _captureActiveTimelinePage();
    _pruneTimelineViewports();
    if (oldWidget.controller != null) {
      // Composer descendants migrate temporary attachment ownership during
      // this same update; dispose the previous owned controller afterwards.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousController.dispose();
      });
    }
  }

  /// 移除监听器并释放编辑、滚动与控制器资源。
  /// Removes listeners and releases composer, scrolling, and controller resources.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.setUserInputSurfaceState(
      foregrounded: false,
      presentedThreadId: null,
    );
    _controller.setDockActivationHandler(null);
    _controller.setOpenSettingsHandler(null);
    _controller.setBrowserInvocationHandler(null);
    _controller.removeListener(_handleControllerUpdate);
    _workspaceFileTabsSubscription.close();
    if (_ownsWorkspaceFileTabsContainer) {
      _workspaceFileTabsContainer.dispose();
    }
    _composer.dispose();
    _sideChatSession?.dispose();
    _pendingTimelineAboveLatest.clear();
    for (final controller in _timelineScrollControllers.values.toSet()) {
      controller.dispose();
    }
    // 显式注入的控制器沿用原有由工作区释放的约定；Provider 创建的
    // 控制器由 ProviderScope 统一释放。
    // Explicitly injected controllers retain the original workspace ownership;
    // Provider-created controllers are disposed by ProviderScope.
    if (widget.controller != null) _controller.dispose();
    super.dispose();
  }

  /// Clears only the current conversation's Dock reminder after the user
  /// returns to the app. Other completed conversations remain badged.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appWasInactive = true;
        _appIsForegrounded = false;
        _syncUserInputSurfaceState();
        return;
      case AppLifecycleState.resumed:
        _appIsForegrounded = true;
        final autoResolutionChanged = _syncUserInputSurfaceState();
        if (autoResolutionChanged && mounted) setState(() {});
        if (!_appWasInactive) return;
        _appWasInactive = false;
        if (_destination != WorkspaceDestination.conversation) return;
        final threadId = _controller.activeThreadId;
        if (threadId == null ||
            !_controller.hasUnacknowledgedCompletion(threadId)) {
          return;
        }
        unawaited(_controller.acknowledgeCompletedThread(threadId));
    }
  }

  /// 处理 Dock 激活回调，只确认当前会话的完成提醒。
  /// Handles Dock activation while acknowledging only the currently visible thread.
  void _handleDockActivation() {
    final threadId = _controller.activeThreadId;
    if (!mounted ||
        _destination != WorkspaceDestination.conversation ||
        threadId == null ||
        !_controller.hasUnacknowledgedCompletion(threadId)) {
      return;
    }
    unawaited(_controller.acknowledgeCompletedThread(threadId));
  }

  /// 智能体发出受支持的浏览器请求后，在会话旁的工作区标签中打开保活浏览器。
  /// Opens the retained browser in a workspace tab beside the conversation.
  void _handleBrowserInvocation(String url) {
    if (!mounted || !_controller.browserEnabled) return;
    setState(() {
      _browserInitialUrl = url;
      _browserNavigationRevision++;
      _browserPageMounted = true;
      _destination = WorkspaceDestination.conversation;
      _activeSidePanelTab = 'browser';
      _sidePanelCollapsed = false;
    });
  }

  Future<bool> _openBrowserLink(Uri uri) async {
    if (!mounted || !_controller.browserEnabled) {
      return false;
    }
    if (_controller.browserLinkOpenMode != BrowserLinkOpenMode.inApp) {
      return false;
    }
    _handleBrowserInvocation(uri.toString());
    return true;
  }

  /// 响应控制器更新；显式注入时由工作区重建，Provider 场景仍由 ref.watch 重建。
  /// Responds to controller updates; the workspace rebuilds explicit injections while ref.watch rebuilds provider state.
  void _handleControllerUpdate() {
    _syncUserInputSurfaceState();
    final workspaceChanged = _synchronizeWorkspaceFileTabs(
      _controller.workspacePath,
    );
    if (workspaceChanged) {
      final removedActiveFile = _activeSidePanelTab.startsWith('file:');
      if (removedActiveFile) {
        _activeSidePanelTab = _fallbackSidePanelTab() ?? '';
        if (_activeSidePanelTab.isEmpty) _sidePanelCollapsed = true;
      }
    }
    if (_selectedSubagentParentThreadId != null &&
        _selectedSubagentParentThreadId != _controller.activeThreadId) {
      _selectedSubagentThreadId = null;
      _selectedSubagentParentThreadId = null;
      _openedSubagentThreadIds.clear();
      _subagentTitles.clear();
      _activeSidePanelTab = _reviewOpen
          ? 'review'
          : _browserPageMounted
          ? 'browser'
          : '';
    }
    if (_controller.isResumingThread) {
      _timelineScrollGeneration++;
      _timelineScrollAnimationViewport = null;
      _timelineScrollAnimationGeneration++;
      _timelineScrollScheduled = false;
      _suppressTimelineScrollAfterThreadResume = true;
      // Cancel an animation that may still be finishing from the previous
      // task before the newly restored timeline is laid out.
      if (_timelineScrollController.hasClients) {
        final position = _timelineScrollController.position;
        if (position.hasPixels) position.jumpTo(position.pixels);
      }
      _activateTimelineViewport(_controller.activeThreadId);
      if (_threadHistoryLoadingKey == _displayedThreadKey ||
          !_controller.hasCachedActiveThreadView) {
        _threadHistoryLoadingKey = _displayedThreadKey;
        _captureActiveTimelinePage();
      } else {
        // A previous first-time viewport may still be settling after its
        // controller has returned to ready. Do not transfer that loading state
        // to a different retained page or reset its saved reading position.
        // 前一个首次打开的视口可能仍在控制器恢复 ready 后校准；不要把其
        // 加载状态传给另一个保活页面，也不要重置后者已保存的阅读位置。
        _threadHistoryLoadingKey = null;
        // The controller can outlive this workspace State (for example after
        // the shell is rebuilt). Recreate the rendering inputs only when the
        // retained UI page is absent, so IndexedStack never falls back to an
        // unrelated task while preserving existing mounted pages unchanged.
        // 控制器可能比当前工作区 State 存活更久（例如外壳重建后）。仅在
        // 保活 UI 页面缺失时重建渲染输入，避免 IndexedStack 回退到无关任务，
        // 已挂载页面则保持不变。
        if (!_timelinePages.containsKey(_displayedThreadKey)) {
          _captureActiveTimelinePage();
        }
      }
      if (widget.controller != null && mounted) setState(() {});
      return;
    }
    _activateTimelineViewport(_controller.activeThreadId);
    final previousStreamingAgentEntryId =
        _timelinePages[_displayedThreadKey]?.streamingAgentEntryId;
    if (_threadHistoryLoadingKey != null &&
        _threadHistoryLoadingKey != _displayedThreadKey) {
      _threadHistoryLoadingKey = null;
    }
    _pruneTimelineViewports();
    _captureActiveTimelinePage();
    final completedStreamingReply =
        previousStreamingAgentEntryId != null &&
        _timelinePages[_displayedThreadKey]?.streamingAgentEntryId == null;
    if (widget.controller != null && mounted) setState(() {});
    _scheduleCompletedThreadAcknowledgementAtBottom(
      _displayedThreadKey,
      _timelineScrollController,
    );
    if (_threadHistoryLoadingKey == _displayedThreadKey) {
      _finishFirstThreadViewport();
      return;
    }
    if (_suppressTimelineScrollAfterThreadResume) {
      _suppressTimelineScrollAfterThreadResume = false;
      return;
    }
    if (!completedStreamingReply &&
        (_timelineFollowsLatest[_displayedThreadKey] ?? true)) {
      _scheduleTimelineScroll();
    }
  }

  void _openSubagentInspector(TimelineEntry entry) {
    final threadId = entry.linkedThreadId;
    if (threadId == null || threadId.isEmpty) return;
    _openSubagentThread(
      threadId: threadId,
      title: entry.title,
      prompt: entry.activityPrompt ?? '',
      status: entry.activityStatus ?? 'working',
    );
  }

  void _openSubagentThread({
    required String threadId,
    required String title,
    required String prompt,
    required String status,
  }) {
    setState(() {
      _selectedSubagentThreadId = threadId;
      _selectedSubagentParentThreadId = _controller.activeThreadId;
      _openedSubagentThreadIds.add(threadId);
      _subagentTitles[threadId] = title;
      _destination = WorkspaceDestination.conversation;
      _activeSidePanelTab = 'subagent:$threadId';
      _sidePanelCollapsed = false;
    });
    unawaited(
      _controller.loadSubagentThread(
        threadId: threadId,
        title: title,
        prompt: prompt,
        status: status,
      ),
    );
  }

  void _returnToMainTask() {
    if (!mounted) return;
    setState(() => _sidePanelCollapsed = true);
  }

  void _toggleSidePanel() {
    if (!mounted) return;
    setState(() => _sidePanelCollapsed = !_sidePanelCollapsed);
  }

  void _handleSidePanelLauncherSelection(String item) {
    switch (item) {
      case 'review':
        _showCodeReview(CodeReviewSource.latestTurn);
      case 'browser':
        setState(() {
          _browserPageMounted = true;
          _destination = WorkspaceDestination.conversation;
          _activeSidePanelTab = 'browser';
          _sidePanelCollapsed = false;
        });
      case 'terminal':
        unawaited(_showRuntime());
      case 'files':
        setState(() {
          _filesPageMounted = true;
          _destination = WorkspaceDestination.conversation;
          _activeSidePanelTab = 'files';
          _sidePanelCollapsed = false;
        });
    }
  }

  void _selectSidePanelTab(String tab) {
    if (!mounted) return;
    setState(() => _activeSidePanelTab = tab);
  }

  String _workspaceFileName(WorkspaceFileReference reference) {
    final segments = reference.uri.pathSegments;
    return segments.isEmpty ? reference.path : segments.last;
  }

  bool _synchronizeWorkspaceFileTabs(String? workspacePath) =>
      _workspaceFileTabsContainer
          .read(workspaceFileTabsProvider(_workspaceFileTabsArgument).notifier)
          .synchronizeWorkspace(workspacePath);

  void _openWorkspaceFile(
    WorkspaceFileReference reference, {
    required String workspacePath,
  }) {
    if (!mounted || _controller.workspacePath != workspacePath) return;
    final tab = _workspaceFileTabsContainer
        .read(workspaceFileTabsProvider(_workspaceFileTabsArgument).notifier)
        .open(reference, workspacePath: workspacePath);
    if (tab == null) return;
    setState(() {
      _destination = WorkspaceDestination.conversation;
      _activeSidePanelTab = tab;
      _sidePanelCollapsed = false;
    });
  }

  void _closeWorkspaceFile(String tab) {
    if (!mounted ||
        !_workspaceFileTabsContainer
            .read(
              workspaceFileTabsProvider(_workspaceFileTabsArgument).notifier,
            )
            .close(tab)) {
      return;
    }
    setState(() {
      if (_activeSidePanelTab != tab) return;
      _activeSidePanelTab = _fallbackSidePanelTab() ?? '';
      if (_activeSidePanelTab.isEmpty) _sidePanelCollapsed = true;
    });
  }

  String? _fallbackSidePanelTab() {
    if (_openedSubagentThreadIds.isNotEmpty) {
      return 'subagent:${_openedSubagentThreadIds.last}';
    }
    final openedWorkspaceFiles = _workspaceFileTabsContainer
        .read(workspaceFileTabsProvider(_workspaceFileTabsArgument))
        .files;
    if (openedWorkspaceFiles.isNotEmpty) {
      return openedWorkspaceFiles.keys.last;
    }
    if (_filesPageMounted) return 'files';
    if (_browserPageMounted) return 'browser';
    if (_reviewOpen) return 'review';
    return null;
  }

  /// Creates a retained controller and remembers when the user deliberately
  /// leaves the latest messages so unrelated state updates do not steal their
  /// reading position.
  ScrollController _timelineControllerFor(ThreadViewportKey key) {
    return _timelineScrollControllers.putIfAbsent(key, () {
      final controller = ScrollController();
      _timelineFollowsLatest[key] = true;
      controller.addListener(() {
        if (!controller.hasClients) return;
        _setTimelineAboveLatest(key, controller.position.extentAfter > 1);
      });
      return controller;
    });
  }

  /// Records user-driven scroll direction separately from programmatic jumps.
  /// This prevents automatic bottom correction from being mistaken for a
  /// deliberate attempt to read older messages.
  void _handleTimelineUserScrollDirection(
    ThreadViewportKey viewportKey,
    ScrollMetrics metrics,
    ScrollDirection direction,
  ) {
    final controller = _timelineScrollControllers[viewportKey];
    if (controller == null || !controller.hasClients) return;
    // Flutter reports `forward` while a normal ListView is being dragged
    // toward its zero offset. From the latest messages that is the user's
    // upward/older-content gesture, so pause follow mode. `reverse` is the
    // return gesture toward the latest messages and may resume following only
    // once the viewport is close to the end.
    if (direction == ScrollDirection.forward) {
      _timelineFollowsLatest[viewportKey] = false;
      if (_timelineScrollAnimationViewport == viewportKey) {
        _timelineScrollAnimationViewport = null;
        _timelineScrollAnimationGeneration++;
      }
      _setTimelineAboveLatest(viewportKey, metrics.extentAfter > 1);
      _timelineScrollRequestGeneration++;
      _timelineScrollScheduled = false;
      return;
    }
    _setTimelineAboveLatest(viewportKey, metrics.extentAfter > 1);
    if (metrics.extentAfter <= 48) {
      _timelineFollowsLatest[viewportKey] = true;
      _scheduleCompletedThreadAcknowledgementAtBottom(viewportKey, controller);
    }
  }

  /// Updates the affordance without rebuilding continuously during a gesture.
  void _setTimelineAboveLatest(
    ThreadViewportKey viewportKey,
    bool aboveLatest,
  ) {
    if (!mounted) return;
    final current = _timelineIsAboveLatest[viewportKey] ?? false;
    if (current == aboveLatest &&
        _pendingTimelineAboveLatest[viewportKey] == null) {
      return;
    }
    // Scroll notifications can be dispatched while the viewport is laying
    // itself out. Mutating the map is harmless, but scheduling a rebuild in
    // that phase triggers Flutter's "Build scheduled during frame" assertion.
    // Keep ordinary event-driven updates synchronous and defer only while the
    // frame's persistent callbacks (build/layout/paint) are running.
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _pendingTimelineAboveLatest.remove(viewportKey);
      _timelineIsAboveLatest[viewportKey] = aboveLatest;
      setState(() {});
      return;
    }
    _pendingTimelineAboveLatest[viewportKey] = aboveLatest;
    if (_timelineAboveLatestUpdateScheduled) return;
    _timelineAboveLatestUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineAboveLatestUpdateScheduled = false;
      if (!mounted) {
        _pendingTimelineAboveLatest.clear();
        return;
      }
      final pendingUpdates = Map<ThreadViewportKey, bool>.from(
        _pendingTimelineAboveLatest,
      );
      _pendingTimelineAboveLatest.clear();
      var changed = false;
      for (final entry in pendingUpdates.entries) {
        if ((_timelineIsAboveLatest[entry.key] ?? false) == entry.value) {
          continue;
        }
        _timelineIsAboveLatest[entry.key] = entry.value;
        changed = true;
      }
      if (changed) setState(() {});
    });
  }

  /// Smoothly returns the active timeline to its actual end and resumes live
  /// updates. A fresh generation cancels any queued automatic correction from
  /// fighting the user-triggered animation.
  void _scrollTimelineToBottom() {
    final viewportKey = _displayedThreadKey;
    final controller = _timelineScrollController;
    if (!controller.hasClients) return;
    _timelineScrollRequestGeneration++;
    _timelineScrollScheduled = false;
    _timelineFollowsLatest[viewportKey] = true;
    final target = controller.position.maxScrollExtent;
    final animationGeneration = ++_timelineScrollAnimationGeneration;
    _timelineScrollAnimationViewport = viewportKey;
    unawaited(
      controller
          .animateTo(
            target,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            if (!mounted ||
                animationGeneration != _timelineScrollAnimationGeneration ||
                _timelineScrollAnimationViewport != viewportKey ||
                viewportKey != _displayedThreadKey ||
                controller != _timelineScrollController ||
                !controller.hasClients) {
              return;
            }
            _timelineScrollAnimationViewport = null;
            // Content can grow while the animation is running. Settle once
            // more at the latest extent without reintroducing a visible jump.
            if (controller.position.extentAfter > 1) {
              controller.jumpTo(controller.position.maxScrollExtent);
            }
            _setTimelineAboveLatest(viewportKey, false);
            _acknowledgeCompletedThreadAtBottom(viewportKey, controller);
          })
          .catchError((_) {
            if (animationGeneration == _timelineScrollAnimationGeneration &&
                _timelineScrollAnimationViewport == viewportKey) {
              _timelineScrollAnimationViewport = null;
            }
          }),
    );
  }

  /// Clears the current task's completion reminder once its latest timeline
  /// content is visible, without acknowledging a background task.
  /// 当前任务的最新时间线内容可见后清除完成提醒，且不误确认后台任务。
  void _acknowledgeCompletedThreadAtBottom(
    ThreadViewportKey viewportKey,
    ScrollController scrollController,
  ) {
    if (!mounted ||
        viewportKey != _displayedThreadKey ||
        viewportKey != _viewportKey(_controller.activeThreadId) ||
        _controller.status != RuntimeStatus.ready ||
        !(_timelineFollowsLatest[viewportKey] ?? false) ||
        !scrollController.hasClients ||
        scrollController.position.extentAfter > 48) {
      return;
    }
    final threadId = viewportKey.threadId;
    if (threadId == null ||
        _controller.isCompletedThreadAcknowledged(threadId)) {
      return;
    }
    // Reaching the latest timeline content marks the in-app reminder as
    // viewed, but the Dock badge remains until the user explicitly opens the
    // task. This keeps the desktop-level notification visible long enough to
    // be noticed even when the completed task is already on screen.
    unawaited(
      _controller.acknowledgeCompletedThread(threadId, clearDockBadge: false),
    );
  }

  /// Re-checks bottom visibility after layout so content collapse or viewport
  /// resizing can acknowledge a completion without moving the user's scroll.
  /// 布局结束后重新核对底部可见性，使内容收起或窗口缩放无需移动滚动位置即可确认完成提醒。
  void _scheduleCompletedThreadAcknowledgementAtBottom(
    ThreadViewportKey viewportKey,
    ScrollController scrollController,
  ) {
    final threadId = viewportKey.threadId;
    if (!mounted ||
        threadId == null ||
        _controller.status != RuntimeStatus.ready ||
        _controller.isCompletedThreadAcknowledged(threadId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _acknowledgeCompletedThreadAtBottom(viewportKey, scrollController);
    });
  }

  void _handleTimelineMetricsChanged(
    ThreadViewportKey viewportKey,
    ScrollMetrics metrics,
  ) {
    final scrollController = _timelineScrollControllers[viewportKey];
    if (scrollController == null) return;
    _setTimelineAboveLatest(viewportKey, metrics.extentAfter > 1);
    if (metrics.extentAfter <= 48) {
      // Metrics notifications can arrive after the user gesture has ended,
      // without a final UserScrollNotification carrying the return direction.
      // Treat the settled bottom as the authoritative latest position.
      _timelineFollowsLatest[viewportKey] = true;
    }
    final viewportDimension = metrics.viewportDimension;
    final previousViewportDimension = _timelineViewportDimensions[viewportKey];
    _timelineViewportDimensions[viewportKey] = viewportDimension;
    final viewportResized =
        previousViewportDimension != null &&
        (viewportDimension - previousViewportDimension).abs() > 0.5;
    if (viewportResized &&
        scrollController.hasClients &&
        scrollController.position.userScrollDirection == ScrollDirection.idle &&
        scrollController.position.extentAfter <= 48) {
      // A viewport resize can reveal the latest entry without any user scroll.
      // That is a genuine return to the end, unlike a short upward gesture.
      _timelineFollowsLatest[viewportKey] = true;
    }
    _scheduleCompletedThreadAcknowledgementAtBottom(
      viewportKey,
      scrollController,
    );
  }

  /// Switches to a task-specific viewport, preserving every visited task's
  /// exact scroll position rather than reusing one shared list controller.
  /// 切换到任务专属视口，保留每个已访问任务的精确滚动位置。
  void _activateTimelineViewport(String? threadId) {
    final key = _viewportKey(threadId);
    if (_displayedThreadKey == key) return;
    _timelineScrollAnimationViewport = null;
    _timelineScrollAnimationGeneration++;
    _displayedThreadKey = key;
    _timelineScrollController = _timelineControllerFor(key);
  }

  /// Captures the active task's rendered timeline inputs so previously opened
  /// tasks can remain mounted as complete pages instead of rebuilding from a
  /// shared timeline when the sidebar selection changes.
  /// 保存当前任务的时间线渲染输入，使已打开任务以完整页面保活，而不是在
  /// 侧栏切换时从共享时间线重新构建。
  void _captureActiveTimelinePage() {
    _timelinePages[_displayedThreadKey] = TimelinePageData(
      // Timeline pages are retained independently of the controller. Normalize
      // a compatible server's out-of-order completion records before they
      // enter that cache, so an already-mounted page cannot preserve the raw
      // arrival order.
      entries: List.unmodifiable(orderAgentMessagePhases(_controller.entries)),
      fileChanges: List.unmodifiable(_controller.fileChanges),
      turnFileChanges: List.unmodifiable(_controller.turnFileChanges),
      turnDiff: _controller.turnDiff,
      showFileChangeSummary:
          _controller.status != RuntimeStatus.running &&
          _controller.fileChanges.isNotEmpty,
      activeActivity: _controller.activeLiveActivity,
      activeCollaborationActivities: List.unmodifiable(
        _controller.activeCollaborationActivities,
      ),
      streamingAgentEntryId: _controller.activeStreamingAgentEntryId,
      activeTurnStartedAt: _controller.status == RuntimeStatus.running
          ? _controller.activeTurnStartedAt
          : null,
      isThinking:
          _controller.status == RuntimeStatus.running &&
          _controller.activeLiveActivity == null,
    );
  }

  ThreadViewportKey _viewportKey(String? threadId) => ThreadViewportKey(
    workspace: _controller.workspacePath,
    threadId: threadId,
  );

  /// Releases viewports whose controller-side page caches were removed by a
  /// project switch, history import, archive, or deletion.
  /// 释放已因项目切换、导入、归档或删除而失效的任务视口。
  void _pruneTimelineViewports() {
    final workspace = _controller.workspacePath;
    final activeThreadId = _controller.activeThreadId;
    final staleKeys = _timelineScrollControllers.keys
        .where(
          (key) =>
              !(key.workspace == workspace && key.threadId == activeThreadId) &&
              (key.threadId == null ||
                  !_controller.isThreadViewCached(
                    workspace: key.workspace ?? '',
                    threadId: key.threadId!,
                  )),
        )
        .toList(growable: false);
    for (final key in staleKeys) {
      final controller = _timelineScrollControllers.remove(key);
      if (_timelineScrollAnimationViewport == key) {
        _timelineScrollAnimationViewport = null;
        _timelineScrollAnimationGeneration++;
      }
      _timelineFollowsLatest.remove(key);
      _timelineIsAboveLatest.remove(key);
      _pendingTimelineAboveLatest.remove(key);
      _timelineViewportDimensions.remove(key);
      _timelinePages.remove(key);
      _fileChangeSummaryExpanded.remove(key);
      _activityListExpanded.removeWhere(
        (activityKey, _) => activityKey.startsWith('${key.storageKey}/'),
      );
      if (controller == null) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) controller.dispose();
      });
    }
  }

  /// 在下一帧无动画定位时间线到最新内容。
  /// Positions the timeline at the latest content without animation next frame.
  void _scheduleTimelineScroll() {
    if (!mounted || _timelineScrollScheduled) return;
    // A user-triggered return animation owns the position until it finishes.
    // Do not mark automatic scrolling as scheduled when it intentionally does
    // nothing, or later streaming updates would be ignored forever.
    if (_timelineScrollAnimationViewport == _displayedThreadKey) return;
    _timelineScrollScheduled = true;
    final requestGeneration = ++_timelineScrollRequestGeneration;
    final generation = _timelineScrollGeneration;
    final viewportKey = _displayedThreadKey;
    final controller = _timelineScrollController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          requestGeneration != _timelineScrollRequestGeneration ||
          generation != _timelineScrollGeneration ||
          viewportKey != _displayedThreadKey ||
          !(_timelineFollowsLatest[viewportKey] ?? true) ||
          !controller.hasClients) {
        if (requestGeneration == _timelineScrollRequestGeneration) {
          _timelineScrollScheduled = false;
        }
        return;
      }
      void settleAtLatest(int remainingFrames) {
        if (!mounted ||
            requestGeneration != _timelineScrollRequestGeneration ||
            generation != _timelineScrollGeneration ||
            viewportKey != _displayedThreadKey ||
            !(_timelineFollowsLatest[viewportKey] ?? true) ||
            !controller.hasClients) {
          return;
        }
        controller.jumpTo(controller.position.maxScrollExtent);
        _timelineFollowsLatest[viewportKey] = true;
        _acknowledgeCompletedThreadAtBottom(viewportKey, controller);
        // A newly inserted live command and the Composer's measured inset can
        // each update the extent on a subsequent frame. Settle a small,
        // bounded number of frames so the active status is not left beneath
        // the floating input area; late async file resolution remains guarded
        // by its own follow-up below.
        if (remainingFrames == 0) {
          _timelineScrollScheduled = false;
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => settleAtLatest(remainingFrames - 1),
        );
      }

      settleAtLatest(3);
    });
  }

  /// Positions a first-time task history while the loading surface is still
  /// visible, then reveals the fully laid-out page without visible scrolling.
  /// 首次任务历史仍被加载画面覆盖时完成定位，随后直接显示完整页面。
  void _finishFirstThreadViewport() {
    if (!mounted) return;
    final viewportKey = _displayedThreadKey;
    final controller = _timelineScrollController;
    final generation = _timelineScrollGeneration;
    _settleFirstThreadViewport(
      viewportKey: viewportKey,
      controller: controller,
      generation: generation,
      attempt: 0,
    );
  }

  /// Repeats the bottom jump until the lazily built list reports a stable
  /// extent. A single jump can use ListView's early height estimate and leave
  /// a long, variable-height history thousands of pixels above its real end.
  /// 重复定位到底部，直到惰性列表的范围稳定；单次跳转可能只采用首屏高度估算，
  /// 让较长且高度不一的历史仍停在真实末尾之前。
  void _settleFirstThreadViewport({
    required ThreadViewportKey viewportKey,
    required ScrollController controller,
    required int generation,
    required int attempt,
    double? previousMaximum,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _timelineScrollGeneration ||
          viewportKey != _displayedThreadKey ||
          viewportKey != _viewportKey(_controller.activeThreadId) ||
          _threadHistoryLoadingKey != viewportKey) {
        return;
      }
      var settled = false;
      double? maximum;
      if (controller.hasClients) {
        final position = controller.position;
        maximum = position.maxScrollExtent;
        final wasAtBottom = position.extentAfter <= 1;
        final maximumStable =
            previousMaximum != null && (maximum - previousMaximum).abs() <= 1;
        position.jumpTo(position.maxScrollExtent);
        _timelineFollowsLatest[viewportKey] = true;
        settled = wasAtBottom && maximumStable;
      }
      if (settled || attempt >= 20) {
        setState(() {
          _threadHistoryLoadingKey = null;
          _suppressTimelineScrollAfterThreadResume = false;
        });
        _scheduleTimelineScroll();
        return;
      }
      // Force a new layout before checking the corrected lazy-list extent.
      // The loading surface remains visible throughout these internal jumps.
      setState(() {});
      _settleFirstThreadViewport(
        viewportKey: viewportKey,
        controller: controller,
        generation: generation,
        attempt: attempt + 1,
        previousMaximum: maximum,
      );
    });
  }

  /// 打开创建项目弹窗，并将可选的源目录保存为非活动项目。
  /// Opens the create-project dialog and saves optional source folders on an inactive project.
  Future<void> _createWorkspace() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => CreateWorkspaceDialog(
        onCreate: (paths, name) async {
          final created = await _controller.createWorkspace(
            paths.isEmpty ? null : paths.first,
            additionalPaths: paths.skip(1).toList(),
            name: name,
          );
          if (!created && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_controller.lastError ?? '无法创建项目，请稍后再试。')),
            );
          }
          return created;
        },
      ),
    );
  }

  Future<void> _createPermanentWorktreeFor(String primaryPath) async {
    if (primaryPath != _controller.workspacePath) {
      final switched = await _controller.selectWorkspaceAndReconnect(
        primaryPath,
      );
      if (!switched) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_controller.lastError ?? '无法切换到该项目。')),
          );
        }
        return;
      }
    }
    final created = await _controller.createPermanentWorktree();
    if (!created && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.lastError ?? '无法创建永久工作树。')),
      );
    }
  }

  /// 选择并添加一个附加工作区目录。
  /// Selects and adds an additional workspace directory.
  Future<bool> _addWorkspaceDirectory() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '添加目录');
      if (path != null && path.trim().isNotEmpty) {
        await _controller.addWorkspaceRoot(path);
        return true;
      }
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
    }
    return false;
  }

  /// 选择并添加目录到指定工作区，支持编辑非当前项目。
  /// Selects and adds a directory to a specified workspace, including inactive projects.
  Future<bool> _addWorkspaceDirectoryFor(String primaryPath) async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '添加文件夹');
      if (path == null || path.trim().isEmpty) return false;
      await _controller.addWorkspaceRootToWorkspace(primaryPath, path);
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
      return false;
    }
  }

  Future<bool> _forgetInactiveWorkspace(String primaryPath) async {
    final before = _controller.workspaceConfigurations.length;
    await _controller.forgetWorkspace(primaryPath);
    return _controller.workspaceConfigurations.length < before;
  }

  /// 展示可切换工作区列表，以及当前工作区的主目录与附加目录。
  /// Shows switchable workspaces plus the current workspace's primary and additional directories.
  Future<void> _showWorkspaceDirectories() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => CodexWorkspaceDirectoriesDialog(
        overrideController: widget.controller,
        onAddDirectory: _addWorkspaceDirectory,
        onCreateWorkspace: _createWorkspace,
      ),
    );
  }

  /// 打开与 Codex 桌面端一致的项目编辑器，管理项目名称和源文件夹。
  /// Opens a Codex desktop-style project editor for the project label and source folders.
  Future<void> _showEditWorkspaceDialog([String? requestedPrimary]) async {
    final primary = requestedPrimary ?? _controller.workspacePath;
    if (primary == null) return;
    final configuration = _controller.workspaceConfigurations.firstWhere(
      (candidate) => candidate.primaryPath == primary,
      orElse: () => WorkspaceConfiguration(primaryPath: primary),
    );
    final nameController = TextEditingController(
      text: configuration.name ?? workspaceDirectoryName(primary),
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    final dialogRoute = DialogRoute<void>(
      context: context,
      themes: themes,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => CodexWorkspaceEditDialog(
        primary: primary,
        nameController: nameController,
        overrideController: widget.controller,
        onForgetInactiveWorkspace: _forgetInactiveWorkspace,
        onAddDirectory: _addWorkspaceDirectoryFor,
      ),
    );
    await navigator.push(dialogRoute);
    await dialogRoute.completed;
    nameController.dispose();
  }

  /// 将当前项目的本地历史导出到用户选择的 JSON 文件；文件不包含 API Key。
  Future<bool> _send(ComposerSubmission submission) async {
    final rawPrompt = submission.prompt.trim();
    if (rawPrompt.isEmpty && !submission.hasContext) return false;
    final submittedText = [
      if (rawPrompt.isNotEmpty) rawPrompt,
      ...submission.pastedTexts
          .map((text) => text.trim())
          .where((text) => text.isNotEmpty),
    ].join('\n\n');
    final contextLines = <String>[];
    final additionalInput = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final skillNames = <String>{};
    final selectedSkills = [...submission.skills];
    for (final skill in selectedSkills) {
      if (!skillNames.add(skill.name)) continue;
      additionalInput.add({
        'type': 'skill',
        'name': skill.name,
        'path': skill.path,
      });
    }
    for (final attachment in submission.attachments) {
      final path = attachment.path;
      if (!attachment.isDirectory && isImagePath(path)) {
        imagePaths.add(path);
        additionalInput.add({'type': 'localImage', 'path': path});
      } else {
        // Keep the readable prompt context for compatibility while also
        // sending the App Server's structured mention input for files and
        // directories selected from the Composer.
        additionalInput.add({
          'type': 'mention',
          'name': path
              .split('/')
              .lastWhere((segment) => segment.isNotEmpty, orElse: () => path),
          'path': path,
        });
        contextLines.add('附加路径：$path');
      }
    }
    if (submission.includeWorkspace && _controller.workspacePath != null) {
      contextLines.add('显式附加当前项目：${_controller.workspacePath}');
    }
    final skillPrefix = skillNames.map((name) => '\$$name').join(' ');
    final promptParts = <String>[
      if (skillPrefix.isNotEmpty) skillPrefix,
      submittedText.isEmpty ? '请分析已附加的内容。' : submittedText,
      if (contextLines.isNotEmpty) '\n${contextLines.join('\n')}',
    ];
    final sent = await _controller.sendPrompt(
      promptParts.join(' ').trim(),
      additionalInput: additionalInput,
      additionalContext: submission.includeIdeContext
          ? _controller.ideAdditionalContext
          : null,
      goal: submission.goal,
      planMode: submission.planMode,
      imagePaths: imagePaths,
      useManagedWorktree: submission.useManagedWorktree,
      managedWorktreeId: submission.managedWorktreeId,
      managedWorktreeBaseRef: submission.managedWorktreeBaseRef,
    );
    if (sent) _composer.clear();
    return sent;
  }

  /// Sends a revised historic prompt as the next turn while preserving the
  /// original transcript as an audit record, matching Codex's inline editor.
  Future<bool> _submitEditedUserMessage(
    TimelineEntry entry,
    String text,
  ) async {
    final submission = ComposerSubmission(
      prompt: text.trim(),
      attachments: const [],
      includeWorkspace: false,
      includeIdeContext: false,
      goal: null,
      planMode: false,
      skills: const [],
    );
    return _controller.canSteer
        ? _queueDirection(submission)
        : _send(submission);
  }

  /// Queues composer text and context as a temporary tail item while a turn runs.
  /// 运行中 Composer 的文本与附件上下文先暂存为临时尾项，等待用户明确发送。
  Future<bool> _queueDirection(ComposerSubmission submission) async {
    final rawPrompt = submission.prompt.trim();
    final submittedText = [
      if (rawPrompt.isNotEmpty) rawPrompt,
      ...submission.pastedTexts
          .map((text) => text.trim())
          .where((text) => text.isNotEmpty),
    ].join('\n\n');
    final hasSubmittedContext =
        submission.attachments.isNotEmpty ||
        submission.pastedTexts.isNotEmpty ||
        submission.includeWorkspace ||
        submission.includeIdeContext ||
        submission.goal?.trim().isNotEmpty == true ||
        submission.planMode ||
        submission.skills.isNotEmpty;
    if (rawPrompt.isEmpty && !hasSubmittedContext) return false;
    final contextLines = <String>[];
    final additionalInput = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final selectedSkills = [...submission.skills];
    final skillNames = <String>{};
    for (final skill in selectedSkills) {
      if (!skillNames.add(skill.name)) continue;
      additionalInput.add({
        'type': 'skill',
        'name': skill.name,
        'path': skill.path,
      });
    }
    for (final attachment in submission.attachments) {
      if (!attachment.isDirectory && isImagePath(attachment.path)) {
        imagePaths.add(attachment.path);
        additionalInput.add({'type': 'localImage', 'path': attachment.path});
      } else {
        additionalInput.add({
          'type': 'mention',
          'name': attachment.path
              .split('/')
              .lastWhere(
                (segment) => segment.isNotEmpty,
                orElse: () => attachment.path,
              ),
          'path': attachment.path,
        });
        contextLines.add('附加路径：${attachment.path}');
      }
    }
    if (submission.includeWorkspace && _controller.workspacePath != null) {
      contextLines.add('显式附加当前项目：${_controller.workspacePath}');
    }
    if (submission.goal?.trim() case final goal? when goal.isNotEmpty) {
      contextLines.add('调整目标：$goal');
    }
    final skillPrefix = skillNames.map((name) => '\$$name').join(' ');
    final prompt = <String>[
      if (skillPrefix.isNotEmpty) skillPrefix,
      submittedText.isEmpty ? '请根据附加内容调整当前任务。' : submittedText,
      if (contextLines.isNotEmpty) '\n${contextLines.join('\n')}',
    ].join(' ').trim();
    return _controller.queueTurnSteer(
      PendingTurnSteer(
        displayText: submittedText.isEmpty ? '请根据附加内容调整当前任务。' : submittedText,
        prompt: prompt,
        goal: submission.goal?.trim(),
        planMode: submission.planMode,
        additionalInput: List.unmodifiable(additionalInput),
        imagePaths: List.unmodifiable(imagePaths),
        additionalContext: submission.includeIdeContext
            ? _controller.ideAdditionalContext
            : null,
      ),
    );
  }

  /// 将当前项目的本地历史导出到用户选择的 JSON 文件；文件不包含 API Key。

  /// Exports the current workspace's local history to a user-selected JSON file without API keys.
  Future<void> _exportConversationHistory() async {
    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Codex Desk 历史', extensions: ['json']),
        ],
        suggestedName: 'codex-desk-history.json',
        confirmButtonText: '导出历史',
      );
      if (location == null) return;
      final content = _controller.exportConversationHistory();
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
        name: 'codex-desk-history.json',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本地历史已导出。文件可能包含对话和 Diff，请妥善保管。')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出历史失败：$error')));
      }
    }
  }

  Future<void> _importConversationHistory() async {
    try {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Codex Desk 历史', extensions: ['json']),
        ],
        confirmButtonText: '导入历史',
      );
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入本地历史？'),
          content: const Text(
            '导入会替换当前项目在 Codex Desk 中缓存的任务列表、置顶状态、对话和 Diff。不会恢复 App Server 原始任务，也不会修改项目文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _controller.importConversationHistory(
        await selected.readAsString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本地历史已导入到当前项目。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入历史失败：$error')));
      }
    }
  }

  /// 显示账户状态以及 ChatGPT 和 API Key 登录入口。
  /// 显示账户状态以及 ChatGPT 和 API Key 登录入口。
  /// Shows account status plus ChatGPT and API-key login entry points.
  Future<void> _showAccount() async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          CodexWorkspaceAccountDialog(overrideController: widget.controller),
    );
  }

  /// 展示由 Codex App Server 原生加载的配置来源，不在应用内收集 Provider 凭据。
  /// Shows the configuration source loaded natively by App Server without collecting provider credentials.
  /// 展示由 Codex App Server 原生加载的配置来源，不在应用内收集 Provider 凭据。
  /// Shows the configuration source loaded natively by App Server without collecting provider credentials.
  Future<void> _showCodexConfiguration() async {
    await _controller.refreshCodexConfiguration();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) =>
          CodexConfigurationDialog(overrideController: widget.controller),
    );
  }

  /// 探测并显示 Codex CLI 状态，同时提供路径配置入口。
  /// Probes and shows Codex CLI status while offering path configuration.
  /// 探测并显示 Codex CLI 状态，同时提供路径配置入口。
  /// Probes and shows Codex CLI status while offering path configuration.
  Future<void> _showRuntime() async {
    await _controller.inspectRuntime();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => CodexWorkspaceRuntimeDialog(
        overrideController: widget.controller,
        onCopyDiagnostics: _copyRuntimeDiagnosticReport,
        onExportDiagnostics: _exportRuntimeDiagnosticReport,
      ),
    );
  }

  Future<void> _copyRuntimeDiagnosticReport() async {
    await Clipboard.setData(
      ClipboardData(text: _controller.buildRuntimeDiagnosticReport()),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制脱敏运行时诊断。')));
    }
  }

  /// 再次生成脱敏诊断报告并保存为用户选择的本地文本文件。
  /// Rebuilds the redacted diagnostic report and saves it as a user-selected local text file.
  Future<void> _exportRuntimeDiagnosticReport() async {
    final location = await getSaveLocation(
      suggestedName: 'codex-desk-diagnostics.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Text', extensions: ['txt']),
      ],
    );
    if (location == null) return;
    try {
      await File(
        location.path,
      ).writeAsString(_controller.buildRuntimeDiagnosticReport(), flush: true);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已导出脱敏运行时诊断。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出诊断失败：${error.toString()}')));
      }
    }
  }

  /// 请求新名称并重命名指定历史线程。
  /// Requests a new name and renames a specified history thread.
  Future<void> _renameThread(CodexThread thread) async {
    final name = TextEditingController(text: thread.name ?? thread.preview);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => CodexWorkspaceRenameThreadDialog(controller: name),
    );
    name.dispose();
    if (nextName != null && nextName.trim().isNotEmpty) {
      await _controller.renameThread(thread, nextName);
    }
  }

  /// Archives a specified history thread immediately.
  Future<void> _archiveThread(CodexThread thread) async {
    await _archiveThreads([thread]);
  }

  /// 显示确认后因状态变化而未归档任务的明确原因。
  /// Explains tasks left unarchived after a confirmed submission.
  void _showArchiveResultFeedback(ThreadArchiveResult result) {
    if (result.archivedIds.isEmpty &&
        result.runningThreadIds.isNotEmpty &&
        result.updatingThreadIds.isEmpty &&
        result.unavailableThreadIds.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('运行中的任务不能归档，请先停止任务。')));
      return;
    }
    final reasons = <String>[];
    if (result.runningThreadIds.isNotEmpty) {
      reasons.add('跳过 ${result.runningThreadIds.length} 个运行中的任务');
    }
    if (result.updatingThreadIds.isNotEmpty) {
      reasons.add('${result.updatingThreadIds.length} 个任务正在处理中');
    }
    if (result.unavailableThreadIds.isNotEmpty) {
      reasons.add('${result.unavailableThreadIds.length} 个任务因运行时不可用未归档');
    }
    if (reasons.isEmpty) return;
    final prefix = result.archivedIds.isEmpty
        ? ''
        : '已归档 ${result.archivedIds.length} 个任务；';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$prefix${reasons.join('；')}。')));
  }

  /// Archives threads immediately and returns success and skip details.
  Future<ThreadArchiveResult?> _archiveThreads(
    List<CodexThread> threads,
  ) async {
    if (threads.isEmpty) return ThreadArchiveResult();
    final result = await _controller.archiveThreads(threads);
    if (mounted) _showArchiveResultFeedback(result);
    return result;
  }

  /// 二次确认后永久删除任务及 App Server 定义的派生任务，删除无法恢复。
  /// Permanently deletes a task and App Server-defined descendants after confirmation; deletion cannot be undone.
  Future<void> _deleteThread(CodexThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => CodexWorkspaceDeleteThreadDialog(thread: thread),
    );
    if (confirmed == true) await _controller.deleteThread(thread);
  }

  /// 刷新并显示归档线程，允许用户恢复线程。
  /// Refreshes and shows archived threads, allowing the user to restore one.
  Future<void> _showArchivedThreads() async {
    await _controller.refreshArchivedThreads();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => CodexWorkspaceArchivedThreadsDialog(
        overrideController: widget.controller,
        onDelete: _deleteThread,
      ),
    );
  }

  /// Opens the workbench review surface with the requested data source.
  /// 以指定数据源打开工作台内嵌审查界面。
  Future<void> _showCodeReview([
    CodeReviewSource source = CodeReviewSource.latestTurn,
  ]) async {
    if (!mounted) return;
    setState(() {
      _destination = WorkspaceDestination.conversation;
      _reviewSource = source;
      _reviewOpen = true;
      _activeSidePanelTab = 'review';
      _sidePanelCollapsed = false;
    });
    if (source == CodeReviewSource.latestTurn) {
      await _controller.ensureFileChangeDiffs();
    } else {
      await _controller.refreshGitReview();
    }
  }

  void _changeCodeReviewSource(CodeReviewSource source) {
    if (mounted) setState(() => _reviewSource = source);
  }

  /// 撤销当前摘要对应的文件改动，并用非阻塞反馈说明结果。
  /// Undoes the file changes represented by the current summary and reports the result non-modally.
  Future<void> _undoFileChanges() async {
    final succeeded = await _controller.undoFileChanges();
    if (!mounted) return;
    final message = succeeded
        ? '已撤销本次任务的文件改动。'
        : _controller.fileChangeUndoError ?? '无法撤销本次任务的文件改动。';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 刷新并展示当前项目的 Git 状态和 Diff，以及用户显式触发的 Git 操作。
  /// Refreshes and shows the current project's Git state, diffs, and explicitly triggered Git actions.
  Future<void> _showGitProject() async {
    await _controller.refreshGitProject();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) =>
            GitProjectDialog(controller: controller),
      ),
    );
  }

  /// 刷新并显示插件管理器，支持本地 marketplace 与启用状态。
  /// Refreshes and shows the plugin manager for local marketplaces and states.
  Future<void> _showPlugins() async {
    unawaited(
      Future.wait([
        _controller.refreshPlugins(),
        _controller.refreshMcpServers(),
        _controller.refreshSkills(forceReload: true),
      ]),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) => ExtensionSettingsDialog(
          controller: controller,
          onAddMarketplace: _showAddMarketplace,
          onManageMarketplaces: _showMarketplaces,
        ),
      ),
    );
  }

  /// Opens the scheduled-task workspace instead of covering the active task.
  Future<void> _showScheduledTasks() async {
    if (!mounted) return;
    setState(() => _destination = WorkspaceDestination.scheduledTasks);
  }

  /// Returns to the conversation workbench when a task is selected from the
  /// sidebar, including while a library page is currently visible.
  /// 从侧栏选择任务时返回会话工作台，即使当前正在显示功能库页面。
  void _showConversation() {
    if (!mounted || _destination == WorkspaceDestination.conversation) return;
    setState(() => _destination = WorkspaceDestination.conversation);
    final offset = _settingsReturnTimelineOffset;
    _settingsReturnTimelineOffset = null;
    if (offset == null) return;
    void restoreOffset(int remainingFrames) {
      if (!mounted || !_timelineScrollController.hasClients) return;
      final position = _timelineScrollController.position;
      _timelineScrollController.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      if (remainingFrames > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => restoreOffset(remainingFrames - 1),
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => restoreOffset(1));
  }

  /// Opens the full plugin workspace while the top-bar button keeps its
  /// focused management dialog for compact task-context use.
  Future<void> _showPluginsPage() async {
    if (!mounted) return;
    setState(() => _destination = WorkspaceDestination.plugins);
    unawaited(_controller.refreshPlugins());
  }

  void _showAgents() {
    if (!mounted) return;
    // The inspector's compact "查看全部" action belongs to the current
    // conversation workbench. Keep the full directory available from the
    // sidebar, but expand the existing subagent tabs here instead of
    // replacing the whole work area with AgentsPage.
    final agents = <String, ({String title, String prompt, String status})>{};
    for (final entry in _controller.entries) {
      final threadId = entry.linkedThreadId;
      if (entry.activityKind != 'collaboration' ||
          threadId == null ||
          threadId.isEmpty ||
          entry.sourceItemId?.startsWith('external-bridge-') == true) {
        continue;
      }
      agents[threadId] = (
        title: entry.title,
        prompt: entry.activityPrompt ?? '',
        status: entry.activityStatus ?? 'working',
      );
    }
    for (final activity in _controller.activeCollaborationActivities) {
      final threadId = activity.linkedThreadId;
      if (threadId == null || threadId.isEmpty || activity.isExternalBridge) {
        continue;
      }
      agents.putIfAbsent(
        threadId,
        () => (
          title: activity.label,
          prompt: activity.prompt,
          status: activity.status ?? 'working',
        ),
      );
    }
    if (agents.isEmpty) return;

    setState(() {
      _destination = WorkspaceDestination.conversation;
      _selectedSubagentParentThreadId = _controller.activeThreadId;
      for (final entry in agents.entries) {
        _openedSubagentThreadIds.add(entry.key);
        _subagentTitles[entry.key] = entry.value.title;
      }
      _selectedSubagentThreadId ??= agents.keys.first;
      _activeSidePanelTab = 'subagent:$_selectedSubagentThreadId';
      _sidePanelCollapsed = false;
    });
    for (final entry in agents.entries) {
      unawaited(
        _controller.loadSubagentThread(
          threadId: entry.key,
          title: entry.value.title,
          prompt: entry.value.prompt,
          status: entry.value.status,
        ),
      );
    }
  }

  /// Opens the full directory from the sidebar navigation.
  void _showAgentsDirectory() {
    if (!mounted) return;
    setState(() => _destination = WorkspaceDestination.agents);
  }

  /// Opens the pull-request workspace without starting an unrequested Git
  /// process; the page exposes an explicit refresh control.
  Future<void> _showPullRequests() async {
    if (!mounted) return;
    setState(() => _destination = WorkspaceDestination.pullRequests);
  }

  /// Opens the full application settings workspace from the sidebar footer.
  /// 从侧栏底部打开完整的应用设置工作区。
  void _showSettings() {
    if (!mounted) return;
    if (_timelineScrollController.hasClients) {
      _settingsReturnTimelineOffset = _timelineScrollController.offset;
    }
    setState(() => _destination = WorkspaceDestination.settings);
  }

  /// Opens the scheduling editor from the scheduled-task workspace.
  Future<void> _showScheduledTaskComposer([String? initialPrompt]) async {
    await showDialog<void>(
      context: context,
      builder: (context) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) => ScheduledTasksDialog(
          controller: controller,
          initialPrompt: initialPrompt,
        ),
      ),
    );
  }

  void _startNewConversation() {
    setState(() => _destination = WorkspaceDestination.conversation);
    _controller.createThread();
  }

  void _showTaskSearchShortcut() {
    if (_destination != WorkspaceDestination.conversation) {
      setState(() => _destination = WorkspaceDestination.conversation);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sidebarKey.currentState?.showTaskSearch();
      });
      return;
    }
    _sidebarKey.currentState?.showTaskSearch();
  }

  Widget _withGlobalShortcuts(CodexController controller, Widget child) {
    return Listener(
      onPointerDown: (_) => _recordUserInputConversationActivity(),
      onPointerSignal: (_) => _recordUserInputConversationActivity(),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, _) {
          _recordUserInputConversationActivity();
          return KeyEventResult.ignored;
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.comma, meta: true):
                _showSettings,
            const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                _startNewConversation,
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                _showTaskSearchShortcut,
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (controller.status == RuntimeStatus.running &&
                  controller.activeThreadId != null) {
                unawaited(controller.stopCurrentTurn());
              }
            },
          },
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: child,
          ),
        ),
      ),
    );
  }

  void _recordUserInputConversationActivity() {
    if (_destination == WorkspaceDestination.conversation) {
      _controller.recordUserInputConversationActivity();
    }
  }

  bool _syncUserInputSurfaceState() {
    return _controller.setUserInputSurfaceState(
      foregrounded:
          _appIsForegrounded &&
          _destination == WorkspaceDestination.conversation,
      presentedThreadId: _destination == WorkspaceDestination.conversation
          ? _controller.activeThreadId
          : null,
    );
  }

  void _askCodexAboutGitHubCli() {
    _startNewConversation();
    _composer.text = '请帮我安装并配置 GitHub CLI，以便查看和管理 Pull Request。';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
  }

  void _createPluginWithCodex() {
    _startNewConversation();
    _composer.text = r'$plugin-creator help me create a plugin';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
  }

  /// 输入或选择一个本地/远程 marketplace 来源并交给控制器注册。
  /// Enters or chooses a local/remote marketplace source and registers it.
  Future<void> _showAddMarketplace() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => const AddMarketplaceDialog(),
    );
    if (selected?.trim().isNotEmpty == true) {
      await _controller.addPluginMarketplace(selected!);
    }
  }

  /// 刷新并显示已配置 marketplace，支持 Git 更新与移除。
  /// Refreshes and shows configured marketplaces with Git updates and removal.
  Future<void> _showMarketplaces() async {
    await _controller.refreshMarketplaces();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => CodexWorkspaceMarketplacesDialog(
        overrideController: widget.controller,
        onRemove: _removeMarketplace,
      ),
    );
  }

  /// 二次确认后移除 marketplace，避免误删已配置来源。
  /// Removes a marketplace after confirmation to avoid accidental source deletion.
  Future<void> _removeMarketplace(CodexMarketplace marketplace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除插件市场？'),
        content: Text('“${marketplace.name}”将不再提供可安装插件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.removePluginMarketplace(marketplace);
    }
  }

  /// 构建响应控制器状态的工作区主布局。
  /// Builds the main workspace layout in response to controller state.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? ref.watch(codexControllerProvider)!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _syncUserInputSurfaceState()) setState(() {});
    });
    final workspaceFileTabs = _workspaceFileTabsContainer.read(
      workspaceFileTabsProvider(_workspaceFileTabsArgument),
    );
    final openedWorkspaceFiles =
        workspaceFileTabs.workspacePath == controller.workspacePath
        ? workspaceFileTabs.files
        : const <String, WorkspaceFileReference>{};
    final browserPage = _browserPageMounted
        ? BrowserWorkspacePage(
            key: _browserPanelKey,
            onOpenConversation: _returnToMainTask,
            initialUrl: _browserInitialUrl,
            navigationRevision: _browserNavigationRevision,
            downloadDirectory: controller.browserDownloadDirectory,
            askBeforeDownload: controller.browserAskBeforeDownload,
            restoreTabs: controller.browserRestoreTabs,
            isVisible:
                _destination == WorkspaceDestination.conversation &&
                !_sidePanelCollapsed &&
                _activeSidePanelTab == 'browser',
          )
        : null;
    final filesPage = _filesPageMounted
        ? FilesWorkspacePage(
            key: const ValueKey('files-workspace-page'),
            workspacePath: controller.workspacePath,
            isVisible:
                _destination == WorkspaceDestination.conversation &&
                !_sidePanelCollapsed &&
                _activeSidePanelTab == 'files',
          )
        : null;
    if (_destination == WorkspaceDestination.settings) {
      return _withGlobalShortcuts(
        controller,
        Scaffold(
          body: SafeArea(
            top: false,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => SettingsPage(
                    controller: controller,
                    runtimeConfigurationStore:
                        controller.runtimeConfigurationStore,
                    navigationWidth: _sidebarWidthFor(constraints.maxWidth),
                    themeMode: widget.themeMode,
                    onThemeModeChanged: widget.onThemeModeChanged,
                    highContrast: widget.highContrast,
                    onHighContrastChanged: widget.onHighContrastChanged,
                    onChooseWorkspace: _showWorkspaceDirectories,
                    onShowCodexConfiguration: _showCodexConfiguration,
                    onConfigureRuntime: _showRuntime,
                    onAddMarketplace: _showAddMarketplace,
                    onManageMarketplaces: _showMarketplaces,
                    onShowAccount: _showAccount,
                    onOpenConversation: _showConversation,
                  ),
                ),
                if (browserPage != null)
                  ExcludeFocus(child: Offstage(child: browserPage)),
                if (filesPage != null)
                  ExcludeFocus(child: Offstage(child: filesPage)),
              ],
            ),
          ),
        ),
      );
    }
    return _withGlobalShortcuts(
      controller,
      Scaffold(
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sidebarMaximum = _sidebarMaximumFor(constraints.maxWidth);
              final inspectorMaximum =
                  (constraints.maxWidth - _sidebarWidth - 420)
                      .clamp(_minimumInspectorWidth, _maximumInspectorWidth)
                      .toDouble();
              final sidebarWidth = _sidebarWidthFor(constraints.maxWidth);
              final compact = constraints.maxWidth < 980;
              final inspectorWidth = _inspectorWidth
                  .clamp(_minimumInspectorWidth, inspectorMaximum)
                  .toDouble();
              final workbenchWidth = constraints.maxWidth - sidebarWidth;
              final sidePanelExpanded = !_sidePanelCollapsed;
              final hasSidePanelContents =
                  _reviewOpen ||
                  _browserPageMounted ||
                  _filesPageMounted ||
                  openedWorkspaceFiles.isNotEmpty ||
                  _openedSubagentThreadIds.isNotEmpty;
              final hasSideChat = _sideChatSession != null;
              final hasSidePanelContentsWithChat =
                  hasSidePanelContents || hasSideChat;
              final sidePanelOpen =
                  sidePanelExpanded && hasSidePanelContentsWithChat;
              final showSidePanelLauncher =
                  sidePanelExpanded && !hasSidePanelContentsWithChat;
              final auxiliaryFullHeight = sidePanelOpen && !compact;
              final reviewMaximum = auxiliaryFullHeight
                  ? (workbenchWidth -
                            conversationContentMaxWidth -
                            _auxiliaryPaneAllowance)
                        .clamp(_minimumAuxiliaryWidth, _maximumReviewWidth)
                        .toDouble()
                  : _minimumReviewWidth;
              final reviewWidth = _reviewWidth
                  .clamp(_minimumAuxiliaryWidth, reviewMaximum)
                  .toDouble();
              final animatedSidePanelWidth =
                  sidePanelOpen || showSidePanelLauncher
                  ? reviewWidth + 8
                  : 0.0;
              final sidePanelContents = <String, Widget>{
                if (_reviewOpen)
                  'review': CodeReviewPanel(
                    key: _reviewPanelKey,
                    controller: controller,
                    source: _reviewSource,
                    compact: compact || reviewWidth < _minimumReviewWidth,
                    onSourceChanged: _changeCodeReviewSource,
                    onCollapse: _returnToMainTask,
                  ),
                if (_browserPageMounted) 'browser': browserPage!,
                if (_filesPageMounted) 'files': filesPage!,
                for (final entry in openedWorkspaceFiles.entries)
                  entry.key: isMarkdownFilePath(entry.value.path)
                      ? WorkspaceMarkdownPreview(
                          key: ValueKey('workspace-${entry.key}'),
                          reference: entry.value,
                          workspacePath: workspaceFileTabs.workspacePath!,
                          embedded: true,
                          onClose: () => _closeWorkspaceFile(entry.key),
                          onOpenReference: (reference) => _openWorkspaceFile(
                            reference,
                            workspacePath: workspaceFileTabs.workspacePath!,
                          ),
                        )
                      : WorkspaceSourceFilePreview(
                          key: ValueKey('workspace-${entry.key}'),
                          reference: entry.value,
                          workspacePath: workspaceFileTabs.workspacePath!,
                          onClose: () => _closeWorkspaceFile(entry.key),
                        ),
                for (final id in _openedSubagentThreadIds)
                  'subagent:$id': SubagentThreadPanel(
                    key: ValueKey('subagent-panel-$id'),
                    controller: controller,
                    threadId: id,
                    fallbackTitle: _subagentTitles[id] ?? '子智能体',
                    onOpenSubagent: _openSubagentInspector,
                  ),
                if (_sideChatSession != null)
                  'side-chat': SideChatPanel(
                    session: _sideChatSession!,
                    onClose: _closeSideChat,
                  ),
              };
              final sidePanelLabels = <String, String>{
                if (_reviewOpen) 'review': '审查',
                if (_browserPageMounted) 'browser': '浏览器',
                if (_filesPageMounted) 'files': '文件',
                for (final entry in openedWorkspaceFiles.entries)
                  entry.key: _workspaceFileName(entry.value),
                for (final id in _openedSubagentThreadIds)
                  'subagent:$id': _subagentTitles[id] ?? '子智能体',
                if (_sideChatSession != null) 'side-chat': '侧边聊天',
              };
              final sidePanelTabs = WorkspaceSidePanelTabs(
                key: const ValueKey('full-height-side-panel'),
                contents: sidePanelContents,
                labels: sidePanelLabels,
                activeTab: _activeSidePanelTab,
                onSelect: _selectSidePanelTab,
                onCollapse: _returnToMainTask,
                closableTabs: openedWorkspaceFiles.keys.toSet(),
                onClose: _closeWorkspaceFile,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: sidebarWidth,
                        child: ColoredBox(
                          color: YeknomPalette.of(context).sidebar,
                          child: Column(
                            children: [
                              TopBar(
                                key: const Key('workspace-column-topbar'),
                                controller: controller,
                                themeMode: widget.themeMode,
                                themePreset: widget.themePreset,
                                onThemeModeChanged: widget.onThemeModeChanged,
                                onThemePresetChanged:
                                    widget.onThemePresetChanged,
                                onChooseWorkspace: _showWorkspaceDirectories,
                                onAccount: _showAccount,
                                onCodexConfiguration: _showCodexConfiguration,
                                onPlugins: _showPlugins,
                                showIdentity: true,
                                showControls: false,
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: Sidebar(
                                  key: _sidebarKey,
                                  width: sidebarWidth,
                                  controller: controller,
                                  onChooseWorkspace: _showWorkspaceDirectories,
                                  onEditWorkspace: _showEditWorkspaceDialog,
                                  onCreateWorkspace: () =>
                                      unawaited(_createWorkspace()),
                                  onCreatePermanentWorktree:
                                      _createPermanentWorktreeFor,
                                  onConfigureRuntime: _showRuntime,
                                  onRenameThread: _renameThread,
                                  onArchiveThread: _archiveThread,
                                  onArchiveThreads: _archiveThreads,
                                  onDeleteThread: _deleteThread,
                                  onShowArchivedThreads: _showArchivedThreads,
                                  onExportHistory: _exportConversationHistory,
                                  onImportHistory: _importConversationHistory,
                                  onShowGitProject: _showGitProject,
                                  onShowPlugins: _showPluginsPage,
                                  onShowAgents: _showAgentsDirectory,
                                  onShowScheduledTasks: _showScheduledTasks,
                                  onShowPullRequests: _showPullRequests,
                                  onShowSettings: _showSettings,
                                  onOpenConversation: _showConversation,
                                  onNewConversation: _startNewConversation,
                                  destination: _destination,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      PaneResizeHandle(
                        key: const Key('sidebar-resize-handle'),
                        onDragDelta: (delta) {
                          final nextWidth = (_sidebarWidth + delta)
                              .clamp(_minimumSidebarWidth, sidebarMaximum)
                              .toDouble();
                          if (nextWidth == _sidebarWidth) return;
                          setState(() => _sidebarWidth = nextWidth);
                          widget.onSidebarWidthChanged?.call(nextWidth);
                        },
                      ),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _destination == WorkspaceDestination.scheduledTasks
                                ? ScheduledTasksPage(
                                    controller: controller,
                                    onCreate: _showScheduledTaskComposer,
                                  )
                                : _destination == WorkspaceDestination.plugins
                                ? PluginsPage(
                                    controller: controller,
                                    onAddMarketplace: _showAddMarketplace,
                                    onOpenSettings: _showPlugins,
                                    onCreatePlugin: _createPluginWithCodex,
                                  )
                                : _destination == WorkspaceDestination.agents
                                ? AgentsPage(
                                    controller: controller,
                                    onOpenSubagent: _openSubagentThread,
                                  )
                                : _destination ==
                                      WorkspaceDestination.pullRequests
                                ? PullRequestsPage(
                                    controller: controller,
                                    onOpenGitProject: _showGitProject,
                                    onAskCodex: _askCodexAboutGitHubCli,
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: SizedBox(
                                                width:
                                                    !compact &&
                                                        !auxiliaryFullHeight
                                                    ? (workbenchWidth -
                                                              (inspectorWidth *
                                                                  2) -
                                                              8)
                                                          .clamp(
                                                            0.0,
                                                            double.infinity,
                                                          )
                                                          .toDouble()
                                                    : null,
                                                child: TopBar(
                                                  key: const Key(
                                                    'workbench-column-topbar',
                                                  ),
                                                  controller: controller,
                                                  themeMode: widget.themeMode,
                                                  themePreset:
                                                      widget.themePreset,
                                                  onThemeModeChanged:
                                                      widget.onThemeModeChanged,
                                                  onThemePresetChanged: widget
                                                      .onThemePresetChanged,
                                                  onChooseWorkspace:
                                                      _showWorkspaceDirectories,
                                                  onAccount: _showAccount,
                                                  onCodexConfiguration:
                                                      _showCodexConfiguration,
                                                  onPlugins: _showPlugins,
                                                  showIdentity: false,
                                                  showControls: true,
                                                  showTaskContext: true,
                                                  onShowFileChanges: () =>
                                                      _showCodeReview(
                                                        CodeReviewSource
                                                            .latestTurn,
                                                      ),
                                                  sidePanelExpanded:
                                                      sidePanelExpanded,
                                                  onToggleSidePanel:
                                                      sidePanelOpen
                                                      ? null
                                                      : _toggleSidePanel,
                                                ),
                                              ),
                                            ),
                                            const Divider(height: 1),
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        WorkspaceFileOpenScope(
                                                          onOpenFile:
                                                              _openWorkspaceFile,
                                                          child: BrowserLinkOpenScope(
                                                            onOpenBrowserLink:
                                                                _openBrowserLink,
                                                            child: ConversationPane(
                                                              controller:
                                                                  controller,
                                                              composer:
                                                                  _composer,
                                                              timelinePages:
                                                                  _timelinePages,
                                                              timelineScrollControllers:
                                                                  _timelineScrollControllers,
                                                              activeTimelinePageKey:
                                                                  _displayedThreadKey,
                                                              threadHistoryLoading:
                                                                  _threadHistoryLoading,
                                                              fileChangeSummaryExpanded:
                                                                  (pageKey) =>
                                                                      _fileChangeSummaryExpanded[pageKey] ??
                                                                      false,
                                                              onFileChangeSummaryExpandedChanged:
                                                                  (
                                                                    pageKey,
                                                                    expanded,
                                                                  ) {
                                                                    setState(() {
                                                                      _fileChangeSummaryExpanded[pageKey] =
                                                                          expanded;
                                                                    });
                                                                  },
                                                              activityExpanded:
                                                                  (
                                                                    pageKey,
                                                                    activityId,
                                                                  ) =>
                                                                      _activityListExpanded['${pageKey.storageKey}/$activityId'] ??
                                                                      false,
                                                              onTimelineMetricsChanged:
                                                                  _handleTimelineMetricsChanged,
                                                              onTimelineUserScrollDirection:
                                                                  _handleTimelineUserScrollDirection,
                                                              showScrollToBottom:
                                                                  _timelineIsAboveLatest[_displayedThreadKey] ??
                                                                  false,
                                                              onScrollToBottom:
                                                                  _scrollTimelineToBottom,
                                                              onActivityExpandedChanged:
                                                                  (
                                                                    pageKey,
                                                                    activityId,
                                                                    expanded,
                                                                  ) {
                                                                    setState(() {
                                                                      _activityListExpanded['${pageKey.storageKey}/$activityId'] =
                                                                          expanded;
                                                                    });
                                                                  },
                                                              onSend: _send,
                                                              onQueueSteer:
                                                                  _queueDirection,
                                                              onReview: () =>
                                                                  _showCodeReview(
                                                                    CodeReviewSource
                                                                        .latestTurn,
                                                                  ),
                                                              onUndo:
                                                                  _undoFileChanges,
                                                              onOpenSubagent:
                                                                  _openSubagentInspector,
                                                              onSubmitUserMessageEdit:
                                                                  _submitEditedUserMessage,
                                                              onSetGoal: controller
                                                                  .setActiveGoalFromMessage,
                                                              onOpenSideChat:
                                                                  _openSideChat,
                                                              sideChatEnabled:
                                                                  !_reviewOpen &&
                                                                  _sideChatSession ==
                                                                      null &&
                                                                  controller
                                                                      .canOpenSideChat,
                                                            ),
                                                          ),
                                                        ),
                                                        if (_threadHistoryLoading)
                                                          Positioned.fill(
                                                            child: IgnorePointer(
                                                              child: ColoredBox(
                                                                key: const Key(
                                                                  'thread-history-loading',
                                                                ),
                                                                color:
                                                                    YeknomPalette.of(
                                                                      context,
                                                                    ).module,
                                                                child: const Center(
                                                                  child:
                                                                      CodexLoadingMark(),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        if (compact &&
                                                            hasSidePanelContentsWithChat)
                                                          ExcludeFocus(
                                                            excluding:
                                                                !sidePanelOpen,
                                                            child: Offstage(
                                                              offstage:
                                                                  !sidePanelOpen,
                                                              child:
                                                                  sidePanelTabs,
                                                            ),
                                                          ),
                                                        if (!compact &&
                                                            !sidePanelExpanded &&
                                                            !showSidePanelLauncher &&
                                                            _destination ==
                                                                WorkspaceDestination
                                                                    .conversation)
                                                          Positioned(
                                                            top: 0,
                                                            right: 0,
                                                            width:
                                                                inspectorWidth +
                                                                8,
                                                            height: 500,
                                                            child: Offstage(
                                                              offstage:
                                                                  !_sidePanelCollapsed,
                                                              child: Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .stretch,
                                                                children: [
                                                                  PaneResizeHandle(
                                                                    key: const Key(
                                                                      'inspector-resize-handle',
                                                                    ),
                                                                    onDragDelta: (delta) => setState(() {
                                                                      _inspectorWidth =
                                                                          (_inspectorWidth -
                                                                                  delta)
                                                                              .clamp(
                                                                                _minimumInspectorWidth,
                                                                                inspectorMaximum,
                                                                              )
                                                                              .toDouble();
                                                                    }),
                                                                  ),
                                                                  SizedBox(
                                                                    width:
                                                                        inspectorWidth,
                                                                    child: Inspector(
                                                                      width:
                                                                          inspectorWidth,
                                                                      controller:
                                                                          controller,
                                                                      onShowTaskChanges: () => _showCodeReview(
                                                                        CodeReviewSource
                                                                            .latestTurn,
                                                                      ),
                                                                      onShowGitProject: () => _showCodeReview(
                                                                        CodeReviewSource
                                                                            .gitWorkspace,
                                                                      ),
                                                                      onShowAgents:
                                                                          _showAgents,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!compact)
                                        WorkspaceDesktopSidePanel(
                                          expanded: sidePanelExpanded,
                                          panelOpen: sidePanelOpen,
                                          hasContents: hasSidePanelContents,
                                          width: animatedSidePanelWidth,
                                          minimumContentWidth:
                                              _sidePanelCollapsed ||
                                                  _browserPageMounted ||
                                                  _filesPageMounted ||
                                                  openedWorkspaceFiles
                                                      .isNotEmpty
                                              ? _minimumAuxiliaryWidth
                                              : 8.0,
                                          contents: sidePanelTabs,
                                          onResize: (delta) => setState(() {
                                            _reviewWidth =
                                                (_reviewWidth - delta)
                                                    .clamp(
                                                      _minimumAuxiliaryWidth,
                                                      reviewMaximum,
                                                    )
                                                    .toDouble();
                                          }),
                                          onLauncherSelect:
                                              _handleSidePanelLauncherSelection,
                                        ),
                                    ],
                                  ),
                            if (_destination !=
                                    WorkspaceDestination.conversation &&
                                hasSidePanelContents)
                              ExcludeFocus(
                                child: Offstage(child: sidePanelTabs),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_destination == WorkspaceDestination.conversation &&
                      !sidePanelOpen)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Builder(
                        builder: (context) {
                          final palette = YeknomPalette.of(context);
                          return IconButton(
                            key: Key(
                              sidePanelExpanded
                                  ? 'side-panel-collapse'
                                  : 'side-panel-expand',
                            ),
                            tooltip: sidePanelExpanded ? '收起右侧工作区' : '展开右侧工作区',
                            onPressed: _toggleSidePanel,
                            style: IconButton.styleFrom(
                              backgroundColor: palette.selected,
                              minimumSize: const Size.square(40),
                              maximumSize: const Size.square(40),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Icon(
                              Icons.view_sidebar_outlined,
                              size: 16,
                              color: palette.trace,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 提供鼠标悬停反馈和宽度约束的桌面双栏分隔条。
/// Desktop split-pane divider with hover feedback and bounded width adjustment.
