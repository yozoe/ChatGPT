// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_conversation_viewport_state.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_timeline_page_data.dart';

class ConversationViewport extends StatefulWidget {
  const ConversationViewport({
    required this.controller,
    required this.timelinePages,
    required this.timelineScrollControllers,
    required this.activeTimelinePageKey,
    required this.threadHistoryLoading,
    required this.fileChangeSummaryExpanded,
    required this.onFileChangeSummaryExpandedChanged,
    required this.activityExpanded,
    required this.onTimelineMetricsChanged,
    required this.onTimelineUserScrollDirection,
    required this.showScrollToBottom,
    required this.onScrollToBottom,
    required this.onActivityExpandedChanged,
    required this.onReview,
    required this.onUndo,
    required this.onOpenSubagent,
    required this.onSubmitUserMessageEdit,
    required this.bottomOverlay,
  });

  final CodexController controller;
  final Map<ThreadViewportKey, TimelinePageData> timelinePages;
  final Map<ThreadViewportKey, ScrollController> timelineScrollControllers;
  final ThreadViewportKey activeTimelinePageKey;
  final bool threadHistoryLoading;
  final bool Function(ThreadViewportKey pageKey) fileChangeSummaryExpanded;
  final void Function(ThreadViewportKey pageKey, bool expanded)
  onFileChangeSummaryExpandedChanged;
  final bool Function(ThreadViewportKey pageKey, String activityId)
  activityExpanded;
  final ValueChanged<ScrollMetrics> onTimelineMetricsChanged;
  final void Function(
    ThreadViewportKey pageKey,
    ScrollMetrics metrics,
    ScrollDirection direction,
  )
  onTimelineUserScrollDirection;
  final bool showScrollToBottom;
  final VoidCallback onScrollToBottom;
  final void Function(
    ThreadViewportKey pageKey,
    String activityId,
    bool expanded,
  )
  onActivityExpandedChanged;
  final Future<void> Function() onReview;
  final Future<void> Function() onUndo;
  final ValueChanged<TimelineEntry> onOpenSubagent;
  final Future<bool> Function(TimelineEntry entry, String text)
  onSubmitUserMessageEdit;
  final Widget bottomOverlay;

  @override
  State<ConversationViewport> createState() => ConversationViewportState();
}
