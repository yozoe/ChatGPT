import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_collaboration_activity_badge.dart';

/// Compact, in-progress summary for every child agent in the active turn.
///
/// App Server can start several collaboration calls before any of them
/// completes. Keeping them together mirrors the session transcript while
/// avoiding a duplicate generic live-activity row for each child.
class LiveCollaborationActivitiesRow extends StatelessWidget {
  const LiveCollaborationActivitiesRow({
    required this.activities,
    required this.onOpenSubagent,
    super.key,
  });

  final List<LiveTurnActivity> activities;
  final ValueChanged<LiveTurnActivity> onOpenSubagent;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final labels = activities
        .map((activity) => '${activity.label}：${activity.detail}')
        .join('；');
    return Semantics(
      key: const Key('live-activity-row'),
      liveRegion: true,
      label: labels,
      child: Wrap(
        key: const Key('live-collaboration-activities-row'),
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final activity in activities)
            InkWell(
              key: ValueKey('live-subagent-activity-open-${activity.itemId}'),
              onTap:
                  activity.linkedThreadId == null || activity.isExternalBridge
                  ? null
                  : () => onOpenSubagent(activity),
              borderRadius: BorderRadius.circular(14),
              child: CollaborationActivityBadge(
                label: activity.label,
                agentId: activity.linkedThreadId ?? activity.itemId,
              ),
            ),
          Text(
            '已开始工作',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.muted),
          ),
        ],
      ),
    );
  }
}
