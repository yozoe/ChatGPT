// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

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
