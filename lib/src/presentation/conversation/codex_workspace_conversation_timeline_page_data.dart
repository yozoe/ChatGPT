// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class TimelinePageData {
  const TimelinePageData({
    required this.entries,
    required this.fileChanges,
    required this.turnDiff,
    required this.showFileChangeSummary,
    required this.activeActivity,
    required this.streamingAgentEntryId,
    required this.activeTurnStartedAt,
    required this.isThinking,
  });

  final List<TimelineEntry> entries;
  final List<CodexFileChange> fileChanges;
  final String? turnDiff;
  final bool showFileChangeSummary;
  final LiveTurnActivity? activeActivity;
  final String? streamingAgentEntryId;
  final DateTime? activeTurnStartedAt;
  final bool isThinking;
}
