// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_subagent_avatar.dart';

/// 以头像和名称显示一个子智能体协作活动的紧凑徽标。
/// Compact avatar-and-label badge for one subagent collaboration activity.
class CollaborationActivityBadge extends StatelessWidget {
  const CollaborationActivityBadge({
    super.key,
    required this.label,
    required this.agentId,
  });

  final String label;
  final String agentId;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.ack.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SubagentAvatar(agentId: agentId, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.trace),
            ),
          ),
        ],
      ),
    );
  }
}
