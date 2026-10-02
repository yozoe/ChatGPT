// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ConversationTimelineItem {
  const ConversationTimelineItem.entry(this.entry, this.entryIndex)
    : activities = null,
      completedTurnEntries = null,
      elapsedEntries = null;

  const ConversationTimelineItem.activities(this.activities, this.entryIndex)
    : entry = null,
      completedTurnEntries = null,
      elapsedEntries = null;

  const ConversationTimelineItem.completedTurn(
    this.entry,
    this.completedTurnEntries,
    this.entryIndex,
  ) : activities = null,
      elapsedEntries = null;

  const ConversationTimelineItem.elapsedGroup(
    this.elapsedEntries,
    this.entryIndex,
  ) : entry = null,
      activities = null,
      completedTurnEntries = null;

  final TimelineEntry? entry;
  final List<TimelineEntry>? activities;
  final List<TimelineEntry>? completedTurnEntries;
  final List<TimelineEntry>? elapsedEntries;
  final int entryIndex;

  String get stableId =>
      entry?.id ?? activities?.first.id ?? elapsedEntries!.first.id;
}
