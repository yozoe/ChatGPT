// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_collaboration_activity_badge.dart';

class ConversationStatusActivityRow extends StatelessWidget {
  const ConversationStatusActivityRow({
    required this.entry,
    this.onOpenSubagent,
  });

  final TimelineEntry entry;
  final VoidCallback? onOpenSubagent;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final failed = entry.activityStatus == 'failed';
    final statusColor = failed ? palette.fault : palette.muted;
    final semantics = entry.detail.isEmpty
        ? entry.title
        : '${entry.title}：${entry.detail}';
    if (entry.activityKind == 'networkRetry') {
      return Semantics(
        key: ValueKey('conversation-activity-${entry.sourceItemId ?? ''}'),
        liveRegion: entry.activityStatus == 'waiting',
        label: semantics,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 3, 6, 3),
          child: Row(
            key: const Key('network-retry-activity'),
            children: [
              Icon(
                Icons.wifi,
                key: const Key('network-retry-icon'),
                size: 15,
                color: palette.muted,
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.muted),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (entry.activityKind == 'collaboration') {
      return Semantics(
        key: ValueKey('conversation-activity-${entry.sourceItemId ?? ''}'),
        label: semantics,
        button: onOpenSubagent != null && entry.linkedThreadId != null,
        child: InkWell(
          key: const Key('subagent-activity-open'),
          onTap: entry.linkedThreadId == null ? null : onOpenSubagent,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
            child: Row(
              children: [
                Flexible(
                  child: CollaborationActivityBadge(
                    label: entry.title,
                    agentId:
                        entry.linkedThreadId ?? entry.sourceItemId ?? entry.id,
                  ),
                ),
                if (entry.detail.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(
                    entry.detail,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: statusColor),
                  ),
                ],
                if (entry.linkedThreadId != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 16, color: palette.muted),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      key: ValueKey('conversation-activity-${entry.sourceItemId ?? ''}'),
      label: semantics,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 3, 6, 3),
        child: Row(
          children: [
            Icon(Icons.build_outlined, size: 15, color: statusColor),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                semantics,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
