// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_timeline_page_data.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_file_change_summary_card.dart';

class ConversationTimeline extends StatelessWidget {
  const ConversationTimeline({
    required this.pageKey,
    required this.data,
    required this.scrollController,
    required this.bottomPadding,
    required this.active,
    required this.fileChangeSummaryExpanded,
    required this.onFileChangeSummaryExpandedChanged,
    required this.activityExpanded,
    required this.onMetricsChanged,
    required this.onUserScrollDirection,
    required this.onActivityExpandedChanged,
    required this.onReview,
    required this.onUndo,
    required this.canUndo,
    required this.undoRunning,
    required this.onOpenSubagent,
    super.key,
  });

  final ThreadViewportKey pageKey;
  final TimelinePageData data;
  final ScrollController scrollController;
  final double bottomPadding;
  final bool active;
  final bool fileChangeSummaryExpanded;
  final ValueChanged<bool> onFileChangeSummaryExpandedChanged;
  final bool Function(String activityId) activityExpanded;
  final ValueChanged<double> onMetricsChanged;
  final void Function(ScrollMetrics metrics, ScrollDirection direction)
  onUserScrollDirection;
  final void Function(String activityId, bool expanded)
  onActivityExpandedChanged;
  final Future<void> Function() onReview;
  final Future<void> Function() onUndo;
  final bool canUndo;
  final bool undoRunning;
  final ValueChanged<TimelineEntry> onOpenSubagent;

  @override
  Widget build(BuildContext context) {
    final timelineItems = conversationTimelineItems(data.entries);
    final liveActivity = active ? data.activeActivity : null;
    final streamingAgentEntryId = active ? data.streamingAgentEntryId : null;
    // The growing reply is already its own live indicator. Rendering a second
    // "writing" row below it makes the entire reply move when item/completed
    // removes that row, especially while the timeline follows the bottom. Keep
    // the row until the first delta creates a visible streaming entry.
    final visibleLiveActivity =
        liveActivity?.kind == 'agentMessage' && streamingAgentEntryId != null
        ? null
        : liveActivity;
    final activeTurnStartedAt = active ? data.activeTurnStartedAt : null;
    final hasLiveStatus = visibleLiveActivity != null;
    var liveElapsedIndex = timelineItems.length;
    if (activeTurnStartedAt != null) {
      final firstTurnOutputIndex = timelineItems.indexWhere((item) {
        final sourceEntry = item.entry ?? item.activities?.firstOrNull;
        return sourceEntry != null &&
            sourceEntry.kind != TimelineKind.user &&
            !sourceEntry.createdAt.isBefore(activeTurnStartedAt);
      });
      if (firstTurnOutputIndex >= 0) {
        liveElapsedIndex = firstTurnOutputIndex;
      }
    }
    Key timelineItemKey(ConversationTimelineItem item) {
      if (item.completedTurnEntries != null) {
        return ValueKey('completed-turn-disclosure-${item.stableId}');
      }
      if (item.activities != null) {
        return ValueKey(
          'timeline-activity-${pageKey.storageKey}-${item.stableId}',
        );
      }
      return ValueKey('timeline-entry-${pageKey.storageKey}-${item.stableId}');
    }

    int listIndexForTimelineIndex(int timelineIndex) =>
        timelineIndex +
        (activeTurnStartedAt != null && timelineIndex >= liveElapsedIndex
            ? 1
            : 0);
    final timelineItemIndexes = <Key, int>{
      for (var index = 0; index < timelineItems.length; index++)
        timelineItemKey(timelineItems[index]): listIndexForTimelineIndex(index),
    };

    // SliverList estimates the scroll extent from the children that have
    // already been laid out.  Timeline rows are intentionally variable-height
    // (Markdown, activity groups, and file summaries), and some of them finish
    // an asynchronous preflight after they are built.  With the default small
    // cache this makes the scrollbar thumb change size while a slow gesture is
    // crossing the history, and the viewport repeatedly corrects its offset.
    // Keep the usual desktop-sized histories laid out before the first gesture
    // so their geometry is stable during scrolling.  The cap prevents an
    // unbounded cache for pathological transcripts; very large histories still
    // retain normal lazy behaviour beyond that bound.
    final itemCount =
        timelineItems.length +
        (activeTurnStartedAt == null ? 0 : 1) +
        (hasLiveStatus ? 1 : 0) +
        (data.showFileChangeSummary ? 1 : 0);
    final timelineCacheExtent = math.min(
      96000.0,
      math.max(2000.0, itemCount * 800.0),
    );

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (active) onMetricsChanged(notification.metrics.viewportDimension);
        return false;
      },
      child: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (active && notification.direction != ScrollDirection.idle) {
            onUserScrollDirection(notification.metrics, notification.direction);
          }
          return false;
        },
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            if (active) {
              onUserScrollDirection(
                notification.metrics,
                ScrollDirection.reverse,
              );
            }
            return false;
          },
          child: ListView.separated(
            key: PageStorageKey('conversation-timeline-${pageKey.storageKey}'),
            controller: scrollController,
            scrollCacheExtent: ScrollCacheExtent.pixels(timelineCacheExtent),
            padding: EdgeInsets.fromLTRB(24, 12, 24, bottomPadding),
            itemCount: itemCount,
            findItemIndexCallback: (key) {
              final timelineIndex = timelineItemIndexes[key];
              if (timelineIndex != null) return timelineIndex;
              if (key ==
                  ValueKey('file-change-summary-${pageKey.storageKey}')) {
                return timelineItems.length +
                    (activeTurnStartedAt == null ? 0 : 1) +
                    (hasLiveStatus ? 1 : 0);
              }
              return null;
            },
            separatorBuilder: (_, index) {
              if (activeTurnStartedAt != null && index == liveElapsedIndex) {
                return const Padding(
                  key: Key('live-elapsed-divider'),
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1),
                );
              }
              return const SizedBox(height: 29);
            },
            itemBuilder: (context, index) {
              if (activeTurnStartedAt != null && index == liveElapsedIndex) {
                return LiveElapsedRow(startedAt: activeTurnStartedAt);
              }
              final timelineIndex =
                  activeTurnStartedAt != null && index > liveElapsedIndex
                  ? index - 1
                  : index;
              if (timelineIndex >= timelineItems.length) {
                var tailIndex = timelineIndex - timelineItems.length;
                if (visibleLiveActivity != null && tailIndex-- == 0) {
                  return visibleLiveActivity.kind == 'commandExecution'
                      ? LiveCommandRow(command: visibleLiveActivity.detail)
                      : LiveActivityRow(
                          activity: visibleLiveActivity,
                          onOpenSubagent:
                              visibleLiveActivity.linkedThreadId == null
                              ? null
                              : () => onOpenSubagent(
                                  TimelineEntry(
                                    kind: TimelineKind.activity,
                                    title: visibleLiveActivity.label,
                                    detail: visibleLiveActivity.detail,
                                    createdAt: DateTime.now(),
                                    sourceItemId: visibleLiveActivity.itemId,
                                    activityKind: 'collaboration',
                                    activityStatus: visibleLiveActivity.status,
                                    linkedThreadId:
                                        visibleLiveActivity.linkedThreadId,
                                    activityPrompt: visibleLiveActivity.prompt,
                                  ),
                                ),
                        );
                }
                if (!data.showFileChangeSummary || tailIndex != 0) {
                  throw StateError(
                    'Unexpected conversation timeline item index.',
                  );
                }
                return FileChangeSummaryCard(
                  key: ValueKey('file-change-summary-${pageKey.storageKey}'),
                  changes: data.fileChanges,
                  turnDiff: data.turnDiff,
                  expanded: fileChangeSummaryExpanded,
                  onExpandedChanged: onFileChangeSummaryExpandedChanged,
                  onReview: onReview,
                  onUndo: onUndo,
                  canUndo: canUndo,
                  undoRunning: undoRunning,
                );
              }
              final item = timelineItems[timelineIndex];
              if (item.completedTurnEntries case final entries?) {
                return CompletedTurnDisclosure(
                  key: timelineItemKey(item),
                  duration: item.entry!,
                  entries: entries,
                  workspacePath: pageKey.workspace,
                  onOpenSubagent: onOpenSubagent,
                );
              }
              if (item.activities case final activities?) {
                final activityId = item.stableId;
                return TimelineActivityList(
                  key: timelineItemKey(item),
                  entries: activities,
                  expanded: activityExpanded(activityId),
                  onExpandedChanged: (expanded) =>
                      onActivityExpandedChanged(activityId, expanded),
                );
              }
              final entry = item.entry!;
              return CodexTimelineEntry(
                entry,
                key: timelineItemKey(item),
                workspacePath: pageKey.workspace,
                streaming: entry.id == streamingAgentEntryId,
                onOpenSubagent: onOpenSubagent,
              );
            },
          ),
        ),
      ),
    );
  }
}
