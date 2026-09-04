// ignore_for_file: use_key_in_widget_constructors

import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_page.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart';
import 'package:chatgpt/src/presentation/agents/codex_workspace_agents_page.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_desktop_side_panel.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:flutter/scheduler.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';

/// 拥有短生命周期界面状态，并把可共享业务状态交由 [CodexController] 管理。
/// Owns short-lived UI state while delegating shared business state to [CodexController].

class CodexWorkspaceState extends ConsumerState<CodexWorkspace>
    with WidgetsBindingObserver {
  final TextEditingController _composer = TextEditingController();
  final ValueNotifier<int> _recordSkillRequest = ValueNotifier(0);
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
    _displayedThreadKey = _viewportKey(_controller.activeThreadId);
    _timelineScrollController = _timelineControllerFor(_displayedThreadKey);
    _captureActiveTimelinePage();
    _controller.addListener(_handleControllerUpdate);
    _controller.setDockActivationHandler(_handleDockActivation);
    _controller.setBrowserInvocationHandler(_handleBrowserInvocation);
    WidgetsBinding.instance.addObserver(this);
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
    previousController.setBrowserInvocationHandler(null);
    _controller = nextController;
    _controller.addListener(_handleControllerUpdate);
    _controller.setDockActivationHandler(_handleDockActivation);
    _controller.setBrowserInvocationHandler(_handleBrowserInvocation);
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
    _controller.setDockActivationHandler(null);
    _controller.setBrowserInvocationHandler(null);
    _controller.removeListener(_handleControllerUpdate);
    _composer.dispose();
    _recordSkillRequest.dispose();
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
        return;
      case AppLifecycleState.resumed:
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

  /// 响应控制器更新；显式注入时由工作区重建，Provider 场景仍由 ref.watch 重建。
  /// Responds to controller updates; the workspace rebuilds explicit injections while ref.watch rebuilds provider state.
  void _handleControllerUpdate() {
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
        unawaited(_showGitProject());
    }
  }

  void _selectSidePanelTab(String tab) {
    if (!mounted) return;
    setState(() => _activeSidePanelTab = tab);
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
    // For a normal downward ListView, `forward` moves the viewport toward
    // older messages (offset decreases); that is the only user gesture that
    // pauses follow mode. `reverse` is the user's return toward the latest
    // content.
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
    final cachedThreadIds = _controller.cachedThreadViewIds;
    final staleKeys = _timelineScrollControllers.keys
        .where(
          (key) =>
              key.workspace != workspace ||
              (key.threadId != null &&
                  key.threadId != activeThreadId &&
                  !cachedThreadIds.contains(key.threadId)),
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
      // 运行时切换与目录保存都可能在弹窗打开期间完成，按钮状态必须随控制器实时更新。
      // Runtime transitions and directory saves may finish while open, so actions must rebuild live.
      builder: (dialogContext) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          final primary = controller.workspacePath;
          final additional = controller.additionalWorkspacePaths;
          final workspaces = controller.workspaceConfigurations;
          return AlertDialog(
            key: const Key('workspace-directories-dialog'),
            title: const Text('工作区'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('每个工作区会独立保存主目录、附加目录和本地历史。新建项目只加入列表，切换后才会连接运行时。'),
                    if (!controller.canChangePrimaryWorkspace) ...[
                      const SizedBox(height: 8),
                      MutedText(
                        '${controller.changePrimaryWorkspaceDisabledReason ?? '当前暂时不能切换工作区。'}仍可新建项目或调整附加目录。',
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          '已保存工作区',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 8),
                        Text('${workspaces.length}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (workspaces.isEmpty)
                      const WorkspaceDirectoryTile(
                        key: Key('saved-workspaces-empty'),
                        path: null,
                        label: '暂无工作区',
                        description: '点击“新建工作区”选择主目录',
                        primary: true,
                      )
                    else
                      ...workspaces.map((workspace) {
                        final active = workspace.primaryPath == primary;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: WorkspaceDirectoryTile(
                            key: ValueKey(
                              'workspace-profile-${workspace.primaryPath}',
                            ),
                            path: workspace.isUnrooted
                                ? null
                                : workspace.primaryPath,
                            label: active ? '当前工作区' : '工作区',
                            description: workspace.isUnrooted
                                ? '未添加源文件夹'
                                : workspace.additionalPaths.isEmpty
                                ? '仅主目录'
                                : '${workspace.additionalPaths.length} 个附加目录',
                            primary: active,
                            trailing: active
                                ? const Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text('当前'),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        key: ValueKey(
                                          'switch-workspace-${workspace.primaryPath}',
                                        ),
                                        onPressed:
                                            !workspace.isUnrooted &&
                                                controller
                                                    .canChangePrimaryWorkspace
                                            ? () => controller
                                                  .selectWorkspaceAndReconnect(
                                                    workspace.primaryPath,
                                                  )
                                            : null,
                                        child: const Text('切换'),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'forget-workspace-${workspace.primaryPath}',
                                        ),
                                        tooltip: '从列表移除（不会删除目录或历史）',
                                        onPressed: () =>
                                            controller.forgetWorkspace(
                                              workspace.primaryPath,
                                            ),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      }),
                    const SizedBox(height: 20),
                    Text(
                      '当前工作区目录',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    WorkspaceDirectoryTile(
                      key: const Key('primary-workspace-directory'),
                      path: primary,
                      label: '主目录',
                      description: '配置、历史、Git 和默认工作位置',
                      primary: true,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          '附加目录',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 8),
                        Text('${additional.length}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (additional.isEmpty)
                      const WorkspaceDirectoryTile(
                        key: Key('additional-workspaces-empty'),
                        path: null,
                        label: '暂无附加目录',
                        description: '添加后，新任务可以同时访问这些目录',
                      )
                    else
                      ...additional.map(
                        (path) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: WorkspaceDirectoryTile(
                            key: ValueKey('additional-workspace-$path'),
                            path: path,
                            label: '附加目录',
                            description: '供后续新任务访问',
                            trailing: IconButton(
                              tooltip: '移除附加目录',
                              onPressed: () async {
                                await controller.removeWorkspaceRoot(path);
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
              OutlinedButton.icon(
                key: const Key('add-workspace-directory-button'),
                onPressed: primary != null
                    ? () async {
                        await _addWorkspaceDirectory();
                      }
                    : null,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('添加目录'),
              ),
              Tooltip(
                message: controller.canCreateWorkspace
                    ? '新建工作区'
                    : '正在保存项目，请稍候。',
                child: FilledButton.icon(
                  key: const Key('create-workspace-button'),
                  onPressed: controller.canCreateWorkspace
                      ? _createWorkspace
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('新建工作区'),
                ),
              ),
            ],
          );
        },
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
    try {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (dialogContext) => ControllerBuilder(
          overrideController: widget.controller,
          builder: (context, controller) {
            final currentPrimary = primary;
            final currentConfiguration = controller.workspaceConfigurations
                .firstWhere(
                  (candidate) => candidate.primaryPath == currentPrimary,
                  orElse: () =>
                      WorkspaceConfiguration(primaryPath: currentPrimary),
                );
            final additional = currentConfiguration.additionalPaths;
            final palette = YeknomPalette.of(context);
            return KeyedSubtree(
              // 保留旧的管理入口 key，便于嵌入方平滑迁移到新的编辑器。
              key: const Key('workspace-directories-dialog'),
              child: Dialog(
                key: const Key('workspace-edit-dialog'),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                backgroundColor: palette.module,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 960,
                    maxHeight: 680,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 34, 40, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '编辑项目',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.5,
                                    ),
                              ),
                            ),
                            IconButton(
                              key: const Key('close-workspace-edit-dialog'),
                              tooltip: '关闭',
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close, size: 25),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        WorkspaceNameField(controller: nameController),
                        const SizedBox(height: 28),
                        Text(
                          '源文件夹',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: WorkspaceSourcesCard(
                            primary: currentConfiguration.isUnrooted
                                ? null
                                : currentPrimary,
                            additional: additional,
                            onRemovePrimary:
                                controller.canChangePrimaryWorkspace
                                ? () async {
                                    final removed =
                                        currentPrimary ==
                                            controller.workspacePath
                                        ? await controller
                                              .removeCurrentWorkspace()
                                        : await _forgetInactiveWorkspace(
                                            currentPrimary,
                                          );
                                    if (removed && dialogContext.mounted) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                  }
                                : null,
                            onRemoveAdditional: (path) =>
                                controller.removeWorkspaceRootFromWorkspace(
                                  currentPrimary,
                                  path,
                                ),
                            onAdd: () =>
                                _addWorkspaceDirectoryFor(currentPrimary),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            TextButton(
                              key: const Key('remove-local-workspace-button'),
                              onPressed: controller.canChangePrimaryWorkspace
                                  ? () async {
                                      final removed =
                                          currentPrimary ==
                                              controller.workspacePath
                                          ? await controller
                                                .removeCurrentWorkspace()
                                          : await _forgetInactiveWorkspace(
                                              currentPrimary,
                                            );
                                      if (removed && dialogContext.mounted) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                    }
                                  : null,
                              style: TextButton.styleFrom(
                                foregroundColor: palette.fault,
                                backgroundColor: palette.fault.withValues(
                                  alpha: 0.14,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: const Text(
                                '移除本地项目',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const Spacer(),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                TextButton(
                                  key: const Key('cancel-workspace-edit'),
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: palette.muted,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 15,
                                    ),
                                  ),
                                  child: const Text(
                                    '取消',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                // 兼容旧版调用方仍查找“关闭”文本；视觉上完全隐藏。
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: 0,
                                    child: TextButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(),
                                      child: const Text('关闭'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 20),
                            FilledButton(
                              key: const Key('save-workspace-edit'),
                              onPressed: () async {
                                await controller.renameWorkspace(
                                  currentPrimary,
                                  nameController.text,
                                );
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                              },
                              style: FilledButton.styleFrom(
                                foregroundColor: Colors.black,
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: const Text(
                                '保存',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      nameController.dispose();
    }
  }

  /// 读取输入框内容、清空编辑器并发送非空任务。
  /// Reads composer content, clears the editor, and sends a nonempty task.
  Future<bool> _send(ComposerSubmission submission) async {
    final rawPrompt = submission.prompt.trim();
    if (rawPrompt.isEmpty && !submission.hasContext) return false;
    final contextLines = <String>[];
    final additionalInput = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final skillNames = <String>{};
    final selectedSkills = [...submission.skills];
    if (submission.recordSkill) {
      final creator = _controller.skills
          .where((skill) => skill.enabled && skill.name == 'skill-creator')
          .firstOrNull;
      if (creator != null) selectedSkills.add(creator);
      contextLines.add('请把本次任务的有效流程整理成一个可复用的 Codex 技能。');
    }
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
        contextLines.add('附加路径：$path');
      }
    }
    if (submission.includeWorkspace && _controller.workspacePath != null) {
      contextLines.add('显式附加当前项目：${_controller.workspacePath}');
    }
    final skillPrefix = skillNames.map((name) => '\$$name').join(' ');
    final promptParts = <String>[
      if (skillPrefix.isNotEmpty) skillPrefix,
      rawPrompt.isEmpty ? '请分析已附加的内容。' : rawPrompt,
      if (contextLines.isNotEmpty) '\n${contextLines.join('\n')}',
    ];
    final sent = await _controller.sendPrompt(
      promptParts.join(' ').trim(),
      additionalInput: additionalInput,
      goal: submission.goal,
      planMode: submission.planMode,
      imagePaths: imagePaths,
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
      goal: null,
      planMode: false,
      recordSkill: false,
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
    final hasSubmittedContext =
        submission.attachments.isNotEmpty ||
        submission.includeWorkspace ||
        submission.goal?.trim().isNotEmpty == true ||
        submission.planMode ||
        submission.recordSkill ||
        submission.skills.isNotEmpty;
    if (rawPrompt.isEmpty && !hasSubmittedContext) return false;
    final contextLines = <String>[];
    final additionalInput = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final selectedSkills = [...submission.skills];
    final skillNames = <String>{};
    if (submission.recordSkill) {
      final creator = _controller.skills
          .where((skill) => skill.enabled && skill.name == 'skill-creator')
          .firstOrNull;
      if (creator != null) selectedSkills.add(creator);
      contextLines.add('请把本次调整的有效流程整理成一个可复用的 Codex 技能。');
    }
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
        contextLines.add('附加路径：${attachment.path}');
      }
    }
    if (submission.includeWorkspace && _controller.workspacePath != null) {
      contextLines.add('显式附加当前项目：${_controller.workspacePath}');
    }
    if (submission.goal?.trim() case final goal? when goal.isNotEmpty) {
      contextLines.add('调整目标：$goal');
    }
    if (submission.planMode) {
      contextLines.add('请先给出执行计划，再继续处理这次调整。');
    }
    final skillPrefix = skillNames.map((name) => '\$$name').join(' ');
    final prompt = <String>[
      if (skillPrefix.isNotEmpty) skillPrefix,
      rawPrompt.isEmpty ? '请根据附加内容调整当前任务。' : rawPrompt,
      if (contextLines.isNotEmpty) '\n${contextLines.join('\n')}',
    ].join(' ').trim();
    return _controller.queueTurnSteer(
      PendingTurnSteer(
        displayText: rawPrompt.isEmpty ? '请根据附加内容调整当前任务。' : rawPrompt,
        prompt: prompt,
        additionalInput: List.unmodifiable(additionalInput),
        imagePaths: List.unmodifiable(imagePaths),
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

  /// 选择并确认导入历史 JSON 到当前项目的本地缓存。
  /// Selects and confirms importing history JSON into the current workspace cache.
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
  /// Shows account status plus ChatGPT and API-key login entry points.
  Future<void> _showAccount() async {
    final apiKey = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          return AlertDialog(
            title: const Text('账户与登录'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前状态：${controller.authLabel}'),
                  if (controller.accountEmail case final email?) ...[
                    const SizedBox(height: 4),
                    Text(email),
                  ],
                  const SizedBox(height: 16),
                  if (!controller.canStopRuntime)
                    const Text('请选择主目录；应用会自动连接本地运行时。')
                  else ...[
                    FilledButton.icon(
                      onPressed: controller.loginInProgress
                          ? null
                          : controller.startChatgptLogin,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('使用 ChatGPT 登录'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiKey,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'OpenAI API Key',
                        hintText: 'sk-…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) async {
                        await controller.loginWithApiKey(value);
                        apiKey.clear();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '密钥不会被此应用写入项目或日志；它会交给本地 Codex 运行时处理。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: controller.loginInProgress
                          ? null
                          : () async {
                              await controller.loginWithApiKey(apiKey.text);
                              apiKey.clear();
                            },
                      child: const Text('使用 API Key 登录'),
                    ),
                    if (controller.loginUrl case final authUrl?) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        authUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          final opened = await launchUrl(
                            Uri.parse(authUrl),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('无法打开浏览器。')),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('在浏览器中打开登录页'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
    apiKey.dispose();
  }

  /// 展示由 Codex App Server 原生加载的配置来源，不在应用内收集 Provider 凭据。
  /// Shows the configuration source loaded natively by App Server without collecting provider credentials.
  Future<void> _showCodexConfiguration() async {
    await _controller.refreshCodexConfiguration();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) => AlertDialog(
          key: const Key('codex-configuration-dialog'),
          title: const Text('Codex 配置'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '模型、Provider、Base URL 和凭据由本地 Codex App Server 按配置优先级直接读取，本应用不再单独收集或保存这些字段。',
                  ),
                  const SizedBox(height: 16),
                  Text('读取状态', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                    controller.codexConfigurationStatusLabel,
                    key: const Key('codex-configuration-status'),
                  ),
                  if (controller.codexConfigurationError case final error?) ...[
                    const SizedBox(height: 4),
                    Text(
                      error,
                      key: const Key('codex-configuration-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text('当前模型', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  SelectableText(
                    controller.configuredModelLabel,
                    key: const Key('codex-configured-model'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '来源：${controller.configuredModelSourceLabel}',
                    key: const Key('codex-configured-model-source'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Provider',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    controller.providerLabel,
                    key: const Key('codex-configured-provider'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '来源：${controller.configuredProviderSourceLabel}',
                    key: const Key('codex-configured-provider-source'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '用户配置文件',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    controller.codexUserConfigPath,
                    key: const Key('codex-configuration-path'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '“已读取”表示模型和 Provider 已由 Codex 运行时解析；凭据、网络和 Base URL 是否可用，仍需成功创建一次任务才能确认。',
                    key: const Key('codex-configuration-verification-note'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '输入框右下角的模型和推理强度选择只影响后续新建任务，不会改写 Codex 配置，也不会覆盖历史任务原有模型。',
                    key: const Key('codex-model-selection-scope-note'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  /// 探测并显示 Codex CLI 状态，同时提供路径配置入口。
  /// Probes and shows Codex CLI status while offering path configuration.
  Future<void> _showRuntime() async {
    await _controller.inspectRuntime();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          final probe = controller.runtimeProbe;
          return AlertDialog(
            title: const Text('Codex CLI 运行时'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (controller.runtimeChecking)
                      const LinearProgressIndicator()
                    else if (probe?.isAvailable == true) ...[
                      const Text('已检测到可用的 Codex CLI。'),
                      const SizedBox(height: 8),
                      SelectableText(probe!.executablePath ?? ''),
                      if (probe.version?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          probe.version!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ] else ...[
                      Text(controller.runtimeError ?? '尚未检测到 Codex CLI。'),
                      const SizedBox(height: 12),
                      const Text('可在终端执行以下官方安装命令：'),
                      const SizedBox(height: 6),
                      const SelectableText(
                        'curl -fsSL https://chatgpt.com/codex/install.sh | sh',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '选择的路径仅保存为本应用设置；启动时会再次验证，不依赖 Finder 的 PATH。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '最近运行时日志（${controller.runtimeLogs.length}/200）',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: controller.runtimeLogs.isEmpty
                              ? null
                              : controller.clearRuntimeLogs,
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      key: const Key('runtime-diagnostics-log'),
                      constraints: const BoxConstraints(maxHeight: 180),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          controller.runtimeLogs.isEmpty
                              ? '本次应用运行中尚未记录 stderr 或协议日志。'
                              : controller.runtimeLogs
                                    .map((entry) => entry.toDiagnosticLine())
                                    .join('\n'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '日志只保留在内存中，最多 200 条；展示和复制前都会脱敏。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                key: const Key('copy-runtime-diagnostics-button'),
                onPressed: _copyRuntimeDiagnosticReport,
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: const Text('复制诊断'),
              ),
              TextButton.icon(
                key: const Key('export-runtime-diagnostics-button'),
                onPressed: _exportRuntimeDiagnosticReport,
                icon: const Icon(Icons.save_alt_outlined, size: 18),
                label: const Text('导出诊断'),
              ),
              TextButton(
                onPressed:
                    controller.canConfigureRuntime &&
                        !controller.runtimeChecking
                    ? () async {
                        final file = await openFile(
                          confirmButtonText: '使用此 Codex CLI',
                        );
                        if (file != null) {
                          await controller.setRuntimeExecutable(file.path);
                        }
                      }
                    : null,
                child: const Text('选择可执行文件'),
              ),
              if (controller.canConfigureRuntime)
                TextButton(
                  onPressed: controller.runtimeChecking
                      ? null
                      : controller.resetRuntimeExecutable,
                  child: const Text('恢复自动检测'),
                ),
              TextButton(
                onPressed: controller.runtimeChecking
                    ? null
                    : controller.inspectRuntime,
                child: const Text('重新检测'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 将当前脱敏运行时诊断复制到系统剪贴板，并提示用户可安全分享的范围。
  /// Copies the current redacted runtime diagnostics to the system clipboard and confirms the shareable scope.
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
      builder: (context) => AlertDialog(
        title: const Text('重命名任务'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: '任务名称'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(name.text),
            child: const Text('保存'),
          ),
        ],
      ),
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
      builder: (context) => AlertDialog(
        title: const Text('永久删除任务？'),
        content: Text(
          '“${thread.title}”及其派生任务会从 Codex 中永久删除，无法恢复。本应用的对应本地缓存引用也会移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
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
      builder: (context) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          return AlertDialog(
            title: const Text('已归档任务'),
            content: SizedBox(
              width: 480,
              height: 420,
              child: switch ((
                controller.archivedThreadsLoading,
                controller.archivedThreadsError,
                controller.archivedThreads,
              )) {
                (true, _, _) => const Center(
                  child: CircularProgressIndicator(),
                ),
                (_, final String error, _) => Center(child: Text(error)),
                (_, _, final List<CodexThread> threads) when threads.isEmpty =>
                  const Center(child: Text('暂无归档任务。')),
                (_, _, final List<CodexThread> threads) => ListView.separated(
                  itemCount: threads.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final thread = threads[index];
                    return ArchivedThreadTile(
                      thread: thread,
                      enabled:
                          controller.status == RuntimeStatus.ready &&
                          !controller.isUnarchivingThread(thread.id) &&
                          !controller.isUpdatingThread(thread.id),
                      restoring: controller.isUnarchivingThread(thread.id),
                      onRestore: () => controller.unarchiveThread(thread),
                      onDelete: () => _deleteThread(thread),
                    );
                  },
                ),
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
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

  void _recordSkillWithCodex() {
    _startNewConversation();
    _composer.clear();
    // The composer is mounted after the destination changes. Deferring the
    // request makes this behave exactly like choosing "录制技能" from its
    // own context menu, including the structured skill input on send.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recordSkillRequest.value++;
    });
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
      builder: (context) => ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          final error = controller.marketplacesError;
          return AlertDialog(
            title: const Text('插件市场'),
            content: SizedBox(
              width: 640,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.pluginSaving) const LinearProgressIndicator(),
                  if (controller.pluginActionProgress case final progress?) ...[
                    const SizedBox(height: 10),
                    Text(
                      progress,
                      key: const Key('marketplace-action-progress'),
                    ),
                  ],
                  if (controller.pluginsError case final actionError?) ...[
                    const SizedBox(height: 10),
                    Text(
                      actionError,
                      style: TextStyle(color: YeknomPalette.of(context).fault),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: controller.marketplacesLoading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                        ? Center(child: Text(error))
                        : controller.marketplaces.isEmpty
                        ? const Center(child: Text('尚未配置插件市场。'))
                        : ListView.separated(
                            itemCount: controller.marketplaces.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final marketplace =
                                  controller.marketplaces[index];
                              return MarketplaceTile(
                                marketplace: marketplace,
                                busy: controller.pluginSaving,
                                onUpgrade: () => controller
                                    .upgradePluginMarketplace(marketplace.name),
                                onRemove: () => _removeMarketplace(marketplace),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: controller.pluginSaving
                    ? null
                    : () => controller.upgradePluginMarketplace(null),
                icon: const Icon(Icons.system_update_outlined),
                label: const Text('刷新所有 Git 市场'),
              ),
              TextButton.icon(
                onPressed:
                    controller.marketplacesLoading || controller.pluginSaving
                    ? null
                    : controller.refreshMarketplaces,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
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
    final browserPage = _browserPageMounted
        ? BrowserWorkspacePage(
            key: _browserPanelKey,
            onOpenConversation: _returnToMainTask,
            initialUrl: _browserInitialUrl,
            navigationRevision: _browserNavigationRevision,
            isVisible:
                _destination == WorkspaceDestination.conversation &&
                !_sidePanelCollapsed &&
                _activeSidePanelTab == 'browser',
          )
        : null;
    if (_destination == WorkspaceDestination.settings) {
      return Scaffold(
        body: SafeArea(
          top: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SettingsPage(
                  controller: controller,
                  navigationWidth: _sidebarWidthFor(constraints.maxWidth),
                  themeMode: widget.themeMode,
                  onThemeModeChanged: widget.onThemeModeChanged,
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
            ],
          ),
        ),
      );
    }
    return Scaffold(
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
                _openedSubagentThreadIds.isNotEmpty;
            final sidePanelOpen = sidePanelExpanded && hasSidePanelContents;
            final showSidePanelLauncher =
                sidePanelExpanded && !hasSidePanelContents;
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
                sidePanelOpen || showSidePanelLauncher ? reviewWidth + 8 : 0.0;
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
              for (final id in _openedSubagentThreadIds)
                'subagent:$id': SubagentThreadPanel(
                  key: ValueKey('subagent-panel-$id'),
                  controller: controller,
                  threadId: id,
                  fallbackTitle: _subagentTitles[id] ?? '子智能体',
                  onOpenSubagent: _openSubagentInspector,
                ),
            };
            final sidePanelLabels = <String, String>{
              if (_reviewOpen) 'review': '审查',
              if (_browserPageMounted) 'browser': '浏览器',
              for (final id in _openedSubagentThreadIds)
                'subagent:$id': _subagentTitles[id] ?? '子智能体',
            };
            final sidePanelTabs = WorkspaceSidePanelTabs(
              key: const ValueKey('full-height-side-panel'),
              contents: sidePanelContents,
              labels: sidePanelLabels,
              activeTab: _activeSidePanelTab,
              onSelect: _selectSidePanelTab,
              onCollapse: _returnToMainTask,
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
                              onThemePresetChanged: widget.onThemePresetChanged,
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
                                width: sidebarWidth,
                                controller: controller,
                                onChooseWorkspace: _showWorkspaceDirectories,
                                onEditWorkspace: _showEditWorkspaceDialog,
                                onCreateWorkspace: () =>
                                    unawaited(_createWorkspace()),
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
                                  onRecordSkill: _recordSkillWithCodex,
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
                                                themePreset: widget.themePreset,
                                                onThemeModeChanged:
                                                    widget.onThemeModeChanged,
                                                onThemePresetChanged:
                                                    widget.onThemePresetChanged,
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
                                                onToggleSidePanel: sidePanelOpen
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
                                                      ConversationPane(
                                                        controller: controller,
                                                        composer: _composer,
                                                        recordSkillRequest:
                                                            _recordSkillRequest,
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
                                                          hasSidePanelContents)
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
                                                          child: Offstage(
                                                            offstage:
                                                                !_sidePanelCollapsed,
                                                            child: Row(
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
                                                                  height: 500,
                                                                  child: Inspector(
                                                                    width:
                                                                        inspectorWidth,
                                                                    controller:
                                                                        controller,
                                                                    onShowTaskChanges: () =>
                                                                        _showCodeReview(
                                                                          CodeReviewSource
                                                                              .latestTurn,
                                                                        ),
                                                                    onShowGitProject: () =>
                                                                        _showCodeReview(
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
                                        minimumContentWidth: _browserPageMounted
                                            ? _minimumAuxiliaryWidth
                                            : 8.0,
                                        contents: sidePanelTabs,
                                        onResize: (delta) => setState(() {
                                          _reviewWidth = (_reviewWidth - delta)
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
                            ExcludeFocus(child: Offstage(child: sidePanelTabs)),
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
    );
  }
}

/// 提供鼠标悬停反馈和宽度约束的桌面双栏分隔条。
/// Desktop split-pane divider with hover feedback and bounded width adjustment.
