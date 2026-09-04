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
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_thread_open_elsewhere_notice.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_failed_turn_retry_notice.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_archived_thread_notice.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_timeline_page_data.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_submission.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_approval_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_elicitation_panel.dart';

class ConversationPane extends StatelessWidget {
  const ConversationPane({
    required this.controller,
    required this.composer,
    required this.recordSkillRequest,
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
    required this.onSend,
    required this.onQueueSteer,
    required this.onReview,
    required this.onUndo,
    required this.onOpenSubagent,
    required this.onSubmitUserMessageEdit,
  });

  final CodexController controller;
  final TextEditingController composer;
  final ValueListenable<int> recordSkillRequest;
  final Map<ThreadViewportKey, TimelinePageData> timelinePages;
  final Map<ThreadViewportKey, ScrollController> timelineScrollControllers;
  final ThreadViewportKey activeTimelinePageKey;
  final bool threadHistoryLoading;
  final bool Function(ThreadViewportKey pageKey) fileChangeSummaryExpanded;
  final void Function(ThreadViewportKey pageKey, bool expanded)
  onFileChangeSummaryExpandedChanged;
  final bool Function(ThreadViewportKey pageKey, String activityId)
  activityExpanded;
  final void Function(ThreadViewportKey pageKey, ScrollMetrics metrics)
  onTimelineMetricsChanged;
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
  final Future<bool> Function(ComposerSubmission submission) onSend;
  final Future<bool> Function(ComposerSubmission submission) onQueueSteer;
  final Future<void> Function() onReview;
  final Future<void> Function() onUndo;
  final ValueChanged<TimelineEntry> onOpenSubagent;
  final Future<bool> Function(TimelineEntry entry, String text)
  onSubmitUserMessageEdit;

  /// 构建时间线、审批提示和任务输入区域。
  /// Builds the timeline, approval prompt, and task composer area.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final showElicitation = controller.shouldShowPendingElicitation;
    final pendingElicitation = showElicitation
        ? controller.pendingElicitation
        : null;
    final pendingApproval = showElicitation ? null : controller.pendingApproval;
    return Column(
      children: [
        if (controller.lastError case final error?
            when !controller.hasThreadWriterConflict &&
                !controller.hasFailedTurnRetry)
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: conversationContentMaxWidth,
              ),
              child: Container(
                key: const Key('conversation-error-banner'),
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.fault.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(error, style: TextStyle(color: palette.fault)),
              ),
            ),
          ),
        Expanded(
          child: ConversationViewport(
            controller: controller,
            timelinePages: timelinePages,
            timelineScrollControllers: timelineScrollControllers,
            activeTimelinePageKey: activeTimelinePageKey,
            threadHistoryLoading: threadHistoryLoading,
            fileChangeSummaryExpanded: fileChangeSummaryExpanded,
            onFileChangeSummaryExpandedChanged:
                onFileChangeSummaryExpandedChanged,
            activityExpanded: activityExpanded,
            onTimelineMetricsChanged: (metrics) =>
                onTimelineMetricsChanged(activeTimelinePageKey, metrics),
            onTimelineUserScrollDirection: onTimelineUserScrollDirection,
            showScrollToBottom: showScrollToBottom,
            onScrollToBottom: onScrollToBottom,
            onActivityExpandedChanged: onActivityExpandedChanged,
            onReview: onReview,
            onUndo: onUndo,
            onOpenSubagent: onOpenSubagent,
            onSubmitUserMessageEdit: onSubmitUserMessageEdit,
            bottomOverlay: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pendingElicitation case final elicitation?)
                  Flexible(
                    child: ElicitationPanel(
                      key: ValueKey(elicitation.requestId),
                      elicitation: elicitation,
                      taskLabel: controller.pendingElicitationTaskLabel,
                      enabled: controller.canRespondToElicitation,
                      onRespond: controller.respondToElicitation,
                    ),
                  )
                else if (pendingApproval case final approval?)
                  Flexible(
                    child: ApprovalPanel(
                      approval: approval,
                      taskLabel: controller.pendingApprovalTaskLabel,
                      enabled: controller.canRespondToApproval,
                      onAccept: () =>
                          controller.respondToApproval(accepted: true),
                      onAllowSimilar: () => controller.respondToApproval(
                        accepted: true,
                        allowSimilar: true,
                      ),
                      onDecline: () =>
                          controller.respondToApproval(accepted: false),
                    ),
                  ),
                if (controller.hasThreadWriterConflict)
                  ThreadOpenElsewhereNotice(
                    retrying: controller.isRetryingThreadWriterConflict,
                    feedback: controller.threadWriterConflictFeedback,
                    onRetry: controller.retryThreadWriterConflict,
                  ),
                if (controller.hasFailedTurnRetry)
                  FailedTurnRetryNotice(
                    error: controller.failedTurnRetryError ?? 'Codex 未能完成当前任务。',
                    retrying: controller.isRetryingFailedTurn,
                    enabled: controller.canRetryFailedTurn,
                    onRetry: controller.retryFailedTurn,
                  ),
                if (controller.hasArchivedThreadRestore)
                  ArchivedThreadNotice(
                    restoring: controller.isRestoringArchivedThread,
                    onRestore: controller.restoreArchivedThread,
                  ),
                ComposerPanel(
                  key: const Key('composer-panel'),
                  controller: controller,
                  composer: composer,
                  recordSkillRequest: recordSkillRequest,
                  onSend: onSend,
                  onQueueSteer: onQueueSteer,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
