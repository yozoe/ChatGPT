// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class TimelineActivityRow extends StatelessWidget {
  const TimelineActivityRow({required this.entry});

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
          padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
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
