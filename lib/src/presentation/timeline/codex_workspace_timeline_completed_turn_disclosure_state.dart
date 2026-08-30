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
  static const _animationDuration = Duration(milliseconds: 180);

  var _expanded = true;
  final _expandedActivityGroups = <String>{};

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final allItems = <ConversationTimelineItem>[];
    appendStandardTimelineItems(
      allItems,
      widget.entries.indexed
          .map((item) => IndexedTimelineEntry(item.$2, item.$1))
          .toList(growable: false),
    );
    final explicitFinalAnswer = widget.entries
        .where(
          (entry) =>
              entry.kind == TimelineKind.agent &&
              entry.agentPhase == 'final_answer',
        )
        .lastOrNull;
    final fallbackFinalAnswer = widget.entries
        .where((entry) => entry.kind == TimelineKind.agent)
        .lastOrNull;
    final finalAnswerId = (explicitFinalAnswer ?? fallbackFinalAnswer)?.id;
    final visibleItems = _expanded
        ? allItems
        : allItems
              .where((item) {
                final entry = item.entry;
                return entry != null &&
                    (entry.id == finalAnswerId ||
                        entry.kind == TimelineKind.approval ||
                        entry.kind == TimelineKind.error);
              })
              .toList(growable: false);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: widget.duration.title,
            child: Material(
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
                      AnimatedRotation(
                        turns: _expanded ? 0.25 : 0,
                        duration: _animationDuration,
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_right,
                          size: 16,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: _animationDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('completed-turn-disclosure-details'),
              width: double.infinity,
              child: visibleItems.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var index = 0;
                            index < visibleItems.length;
                            index++
                          ) ...[
                            _completedTurnDetail(visibleItems[index]),
                            if (index != visibleItems.length - 1)
                              const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (allItems.isNotEmpty)
            const Padding(
              key: Key('completed-turn-disclosure-divider'),
              padding: EdgeInsets.only(top: 8),
              child: Divider(height: 1),
            ),
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
