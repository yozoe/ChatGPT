import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

/// Compact completion summary shown when a persistent Goal reaches completion.
class GoalCompletionSummary extends StatelessWidget {
  const GoalCompletionSummary({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      container: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              key: const Key('goal-completion-summary-icon'),
              size: 16,
              color: palette.ack,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                key: const Key('goal-completion-summary-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
