// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_conversation_timeline_item.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_indexed_timeline_entry.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_completed_turn_disclosure.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_timeline_activity_list.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_codex_timeline_entry.dart';

class CompletedTurnDisclosureState extends State<CompletedTurnDisclosure> {
  var _expanded = true;
  final _expandedActivityGroups = <String>{};

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final detailItems = <ConversationTimelineItem>[];
    appendStandardTimelineItems(
      detailItems,
      widget.entries.indexed
          .map((item) => IndexedTimelineEntry(item.$2, item.$1))
          .toList(growable: false),
    );
    return Semantics(
      container: true,
      button: true,
      expanded: _expanded,
      label: widget.duration.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('completed-turn-disclosure-toggle'),
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                key: const Key('completed-turn-disclosure-content'),
                padding: const EdgeInsets.fromLTRB(7, 4, 5, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.duration.title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 16,
                      color: palette.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (detailItems.isNotEmpty)
            const Padding(
              key: Key('completed-turn-disclosure-divider'),
              padding: EdgeInsets.only(top: 8),
              child: Divider(height: 1),
            ),
          if (_expanded && detailItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var index = 0; index < detailItems.length; index++) ...[
              _completedTurnDetail(detailItems[index]),
              if (index != detailItems.length - 1) const SizedBox(height: 14),
            ],
          ],
        ],
      ),
    );
  }

  Widget _completedTurnDetail(ConversationTimelineItem item) {
    if (item.activities case final activities?) {
      final activityId = item.stableId;
      return TimelineActivityList(
        key: ValueKey('completed-turn-activity-$activityId'),
        entries: activities,
        // Completed operations stay compact until the user explicitly opens
        // the nested activity summary.
        expanded: _expandedActivityGroups.contains(activityId),
        onExpandedChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedActivityGroups.add(activityId);
            } else {
              _expandedActivityGroups.remove(activityId);
            }
          });
        },
      );
    }
    return CodexTimelineEntry(
      item.entry!,
      key: ValueKey('completed-turn-entry-${item.stableId}'),
      workspacePath: widget.workspacePath,
      onOpenSubagent: widget.onOpenSubagent,
    );
  }
}
