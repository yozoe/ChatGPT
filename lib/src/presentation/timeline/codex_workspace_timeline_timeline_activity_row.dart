// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class TimelineActivityRow extends StatelessWidget {
  const TimelineActivityRow({super.key, required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final label = activityLabel(entry);
    return Tooltip(
      message: entry.detail,
      waitDuration: codexHoverPopupDelay,
      child: Semantics(
        label: '$label。${entry.detail}',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 3, 6, 3),
          child: Row(
            children: [
              Icon(activityIcon(entry), size: 19, color: palette.muted),
              const SizedBox(width: 10),
              Expanded(
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
        ),
      ),
    );
  }
}
