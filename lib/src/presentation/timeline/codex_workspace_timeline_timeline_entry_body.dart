// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_conversation_status_activity_row.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_user_message_bubble.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_streaming_agent_text.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown.dart';

class TimelineEntryBody extends StatelessWidget {
  const TimelineEntryBody(
    this.entry, {
    super.key,
    required this.workspacePath,
    this.streaming = false,
    this.preserveViewportOnMarkdownResolve = false,
    this.onOpenSubagent,
    this.onSubmitUserMessageEdit,
    this.onSetGoal,
  });

  final TimelineEntry entry;
  final String? workspacePath;
  final bool streaming;
  final bool preserveViewportOnMarkdownResolve;
  final VoidCallback? onOpenSubagent;
  final Future<bool> Function(TimelineEntry entry, String text)?
  onSubmitUserMessageEdit;
  final Future<bool> Function(String text)? onSetGoal;

  /// 按时间线条目类型构建消息或系统事件视图。
  /// Builds a message or system-event view based on the timeline entry kind.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (entry.kind == TimelineKind.elapsed) {
      return Semantics(
        label: entry.title,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            entry.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    if (entry.kind == TimelineKind.user) {
      return UserMessageBubble(
        entry: entry,
        onSubmitEdit: onSubmitUserMessageEdit,
        onSetGoal: onSetGoal,
      );
    }
    if (entry.kind == TimelineKind.activity) {
      return ConversationStatusActivityRow(
        entry: entry,
        onOpenSubagent: onOpenSubagent,
      );
    }
    if (entry.kind == TimelineKind.agent) {
      return entry.detail.isEmpty
          ? const SizedBox.shrink()
          : Semantics(
              container: true,
              label: 'Codex 回复',
              child: streaming
                  ? StreamingAgentText(entry.detail)
                  : AgentMarkdown(
                      entry.detail,
                      workspacePath: workspacePath,
                      preserveViewportOnResolve:
                          preserveViewportOnMarkdownResolve,
                    ),
            );
    }

    final color = switch (entry.kind) {
      TimelineKind.agent => palette.ack,
      TimelineKind.activity => throw StateError('Handled above.'),
      TimelineKind.command => palette.warning,
      TimelineKind.tool => palette.active,
      TimelineKind.approval => palette.signal,
      TimelineKind.error => palette.fault,
      TimelineKind.system => palette.muted,
      TimelineKind.elapsed => palette.muted,
      TimelineKind.user => throw StateError('Handled above.'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.title,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        if (entry.detail.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectionArea(child: Text(entry.detail)),
        ],
      ],
    );
  }
}
