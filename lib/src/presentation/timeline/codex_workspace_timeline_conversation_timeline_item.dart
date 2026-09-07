// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ConversationTimelineItem {
  const ConversationTimelineItem.entry(this.entry, this.entryIndex)
    : activities = null,
      completedTurnEntries = null;

  const ConversationTimelineItem.activities(this.activities, this.entryIndex)
    : entry = null,
      completedTurnEntries = null;

  const ConversationTimelineItem.completedTurn(
    this.entry,
    this.completedTurnEntries,
    this.entryIndex,
  ) : activities = null;

  final TimelineEntry? entry;
  final List<TimelineEntry>? activities;
  final List<TimelineEntry>? completedTurnEntries;
  final int entryIndex;

  String get stableId => entry?.id ?? activities!.first.id;
}
