// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_collaboration_activity_badge.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_activity_shimmer.dart';

class LiveActivityRow extends StatelessWidget {
  const LiveActivityRow({required this.activity, this.onOpenSubagent});

  final LiveTurnActivity activity;
  final VoidCallback? onOpenSubagent;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final detail = activity.detail;
    final icon = liveActivityIcon(activity.kind);
    final semantics = detail.isEmpty
        ? activity.label
        : '${activity.label}：$detail';
    if (activity.kind == 'collabToolCall') {
      return Semantics(
        key: const Key('live-activity-row'),
        liveRegion: true,
        label: semantics,
        button: onOpenSubagent != null,
        child: InkWell(
          key: const Key('live-subagent-activity-open'),
          onTap: onOpenSubagent,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
            child: Row(
              children: [
                Flexible(
                  child: CollaborationActivityBadge(
                    label: activity.label,
                    agentId: activity.linkedThreadId ?? activity.itemId,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  LiveActivityShimmer(
                    shimmerKey: const Key('live-activity-shimmer'),
                    child: Text(
                      detail,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: palette.muted),
                    ),
                  ),
                ],
                if (onOpenSubagent != null) ...[
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
      key: const Key('live-activity-row'),
      liveRegion: true,
      label: semantics,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 3, 6, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: palette.muted),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: LiveActivityShimmer(
                shimmerKey: const Key('live-activity-shimmer'),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: activity.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.muted,
                          fontWeight: activity.kind == 'reasoning'
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                      if (detail.isNotEmpty)
                        TextSpan(
                          text: ' $detail',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.trace),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
