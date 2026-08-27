// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_timeline_activity_row.dart';

class TimelineActivityList extends StatelessWidget {
  const TimelineActivityList({
    required this.entries,
    required this.expanded,
    required this.onExpandedChanged,
    super.key,
  });

  final List<TimelineEntry> entries;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  static const _animationDuration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final summary = activitySummary(entries);
    return Semantics(
      container: true,
      label: summary,
      expanded: expanded,
      button: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onExpandedChanged(!expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 6, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.manage_search_outlined,
                    size: 20,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: _animationDuration,
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.chevron_right,
                      size: 17,
                      color: palette.faint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: _animationDuration,
            curve: Curves.easeOutCubic,
            // Keep the disclosure at its final width in both states so the
            // transition reveals only vertically, matching Codex's timeline.
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('timeline-activity-disclosure-area'),
              width: double.infinity,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Column(
                        children: [
                          for (final entry in entries)
                            TimelineActivityRow(entry: entry),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
