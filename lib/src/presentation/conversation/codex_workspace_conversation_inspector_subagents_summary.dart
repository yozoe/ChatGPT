import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_subagent_avatar.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Compact inspector summary that opens the complete subagent directory.
class InspectorSubagentsSummary extends StatelessWidget {
  const InspectorSubagentsSummary({
    super.key,
    required this.controller,
    required this.onShowAll,
  });

  final CodexController controller;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final completedAgents = controller.entries
        .where(
          (entry) =>
              entry.activityKind == 'collaboration' &&
              entry.linkedThreadId != null,
        )
        .map(
          (entry) => (
            threadId: entry.linkedThreadId!,
            status: entry.activityStatus ?? 'working',
          ),
        )
        .toList(growable: true);
    for (final activity in controller.activeCollaborationActivities) {
      final threadId = activity.linkedThreadId;
      if (threadId == null ||
          completedAgents.any((agent) => agent.threadId == threadId)) {
        continue;
      }
      completedAgents.add((threadId: threadId, status: 'working'));
    }
    final agents = List.unmodifiable(completedAgents);
    final working = agents
        .where((agent) => agent.status == 'working')
        .toList(growable: false);
    final completed = agents.length - working.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hub_outlined, size: 16, color: palette.trace),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '子智能体',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '完成 $completed',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        InkWell(
          key: const Key('inspector-subagents-open-all'),
          onTap: onShowAll,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                for (final agent in agents.take(3)) ...[
                  SubagentAvatar(agentId: agent.threadId, size: 16),
                  const SizedBox(width: 3),
                ],
                if (agents.isEmpty)
                  Text(
                    '暂无子智能体',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  )
                else ...[
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      working.isEmpty ? '全部已结束' : '${working.length} 个运行中',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ),
                  Text(
                    '查看全部',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: palette.muted),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
