// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_conversation_viewport.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_conversation_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_codex_loading_mark.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_task_plan_panel.dart';

class ConversationViewportState extends State<ConversationViewport> {
  static const _initialBottomOverlayHeight = 172.0;
  static const _fadeHeight = 64.0;
  static const _fadeComposerOverlap = 12.0;
  // Keep a visible breathing space after the final item once it has cleared
  // the floating Composer or task-plan panel.
  static const _timelineBottomClearance = 52.0;

  final GlobalKey _bottomOverlayKey = GlobalKey();
  var _bottomOverlayHeight = _initialBottomOverlayHeight;
  var _overlayMeasureScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleBottomOverlayMeasurement();
  }

  void _scheduleBottomOverlayMeasurement() {
    if (_overlayMeasureScheduled) return;
    _overlayMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayMeasureScheduled = false;
      if (!mounted) return;
      final renderObject = _bottomOverlayKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final measuredHeight = renderObject.size.height;
      if ((measuredHeight - _bottomOverlayHeight).abs() <= 0.5) return;
      final activeScrollController =
          widget.timelineScrollControllers[widget.activeTimelinePageKey];
      final initialPixels = activeScrollController?.hasClients == true
          ? activeScrollController!.position.pixels
          : null;
      final keepLatestVisible =
          activeScrollController?.hasClients == true &&
          activeScrollController!.position.userScrollDirection ==
              ScrollDirection.idle &&
          activeScrollController.position.extentAfter <= 48;
      setState(() => _bottomOverlayHeight = measuredHeight);
      if (keepLatestVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              activeScrollController !=
                  widget.timelineScrollControllers[widget
                      .activeTimelinePageKey] ||
              !activeScrollController.hasClients) {
            return;
          }
          final position = activeScrollController.position;
          if (position.userScrollDirection != ScrollDirection.idle ||
              position.extentAfter > 48 ||
              (initialPixels != null &&
                  (position.pixels - initialPixels).abs() > 0.5)) {
            return;
          }
          position.jumpTo(position.maxScrollExtent);
        });
      }
    });
  }

  bool _handleBottomOverlaySizeChanged(SizeChangedLayoutNotification _) {
    _scheduleBottomOverlayMeasurement();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final plan = widget.controller.status == RuntimeStatus.running
        ? widget.controller.activeTaskPlan
        : null;
    final pages = widget.timelinePages.entries.toList(growable: false);
    final activePage = widget.timelinePages[widget.activeTimelinePageKey];
    final showFloatingThinking =
        widget.controller.status == RuntimeStatus.running &&
        activePage?.isThinking == true &&
        activePage?.activeActivity == null;
    final activePageIndex = pages.indexWhere(
      (page) => page.key == widget.activeTimelinePageKey,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableAboveComposer = math.max(
          100.0,
          constraints.maxHeight - _bottomOverlayHeight - 16,
        );
        final planHeight = availableAboveComposer.clamp(100.0, 340.0);
        final timelineBottomPadding =
            _bottomOverlayHeight +
            (plan == null
                ? _timelineBottomClearance
                : planHeight + _timelineBottomClearance);
        return Stack(
          key: const Key('conversation-viewport-stack'),
          children: [
            Positioned.fill(
              child: ShaderMask(
                key: const Key('composer-bottom-fade'),
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final height = math.max(1.0, bounds.height);
                  final fadeEnd =
                      (1 -
                              ((_bottomOverlayHeight - _fadeComposerOverlap) /
                                  height))
                          .clamp(0.0, 1.0);
                  final fadeStart = (fadeEnd - (_fadeHeight / height)).clamp(
                    0.0,
                    fadeEnd,
                  );
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                      Colors.transparent,
                    ],
                    stops: [0, fadeStart, fadeEnd, 1],
                  ).createShader(bounds);
                },
                child: IndexedStack(
                  index: activePageIndex < 0 ? 0 : activePageIndex,
                  children: [
                    for (final page in pages)
                      ConversationTimeline(
                        key: ValueKey(
                          'conversation-timeline-${page.key.storageKey}',
                        ),
                        pageKey: page.key,
                        data: page.value,
                        scrollController:
                            widget.timelineScrollControllers[page.key]!,
                        bottomPadding: timelineBottomPadding,
                        active: page.key == widget.activeTimelinePageKey,
                        fileChangeSummaryExpanded: widget
                            .fileChangeSummaryExpanded(page.key),
                        onFileChangeSummaryExpandedChanged: (expanded) =>
                            widget.onFileChangeSummaryExpandedChanged(
                              page.key,
                              expanded,
                            ),
                        activityExpanded: (activityId) =>
                            widget.activityExpanded(page.key, activityId),
                        onMetricsChanged: (viewportDimension) =>
                            widget.onTimelineMetricsChanged(
                              page.key,
                              viewportDimension,
                            ),
                        onUserScrollDirection: (metrics, direction) =>
                            widget.onTimelineUserScrollDirection(
                              page.key,
                              metrics,
                              direction,
                            ),
                        onActivityExpandedChanged: (activityId, expanded) =>
                            widget.onActivityExpandedChanged(
                              page.key,
                              activityId,
                              expanded,
                            ),
                        onReview: widget.onReview,
                        onUndo: widget.onUndo,
                        onOpenSubagent: widget.onOpenSubagent,
                        canUndo:
                            page.key == widget.activeTimelinePageKey &&
                            widget.controller.canUndoFileChanges,
                        undoRunning:
                            page.key == widget.activeTimelinePageKey &&
                            widget.controller.fileChangeUndoRunning,
                      ),
                  ],
                ),
              ),
            ),
            if (plan != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: _bottomOverlayHeight + 12,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 620,
                      maxHeight: planHeight,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showFloatingThinking) ...[
                          const IgnorePointer(child: LiveThinkingRow()),
                          const SizedBox(height: 12),
                        ],
                        Flexible(child: TaskPlanPanel(plan: plan)),
                      ],
                    ),
                  ),
                ),
              ),
            if (showFloatingThinking && plan == null)
              Positioned(
                left: 24,
                right: 24,
                bottom: _bottomOverlayHeight + 20,
                child: const IgnorePointer(child: LiveThinkingRow()),
              ),
            if (widget.threadHistoryLoading)
              Positioned.fill(
                bottom: _bottomOverlayHeight,
                child: ColoredBox(
                  key: const Key('thread-history-loading'),
                  color: palette.module,
                  child: const Center(child: CodexLoadingMark()),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: _handleBottomOverlaySizeChanged,
                child: SizeChangedLayoutNotifier(
                  key: _bottomOverlayKey,
                  child: widget.bottomOverlay,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
