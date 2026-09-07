// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

/// 为时间线分页计算提供稳定的条目快照和滚动元数据。
/// Holds a stable timeline snapshot and scroll metadata used by timeline paging.
class TimelinePageData {
  const TimelinePageData({
    required this.entries,
    required this.fileChanges,
    required this.turnDiff,
    required this.showFileChangeSummary,
    required this.activeActivity,
    required this.activeCollaborationActivities,
    required this.streamingAgentEntryId,
    required this.activeTurnStartedAt,
    required this.isThinking,
  });

  final List<TimelineEntry> entries;
  final List<CodexFileChange> fileChanges;
  final String? turnDiff;
  final bool showFileChangeSummary;
  final LiveTurnActivity? activeActivity;
  final List<LiveTurnActivity> activeCollaborationActivities;
  final String? streamingAgentEntryId;
  final DateTime? activeTurnStartedAt;
  final bool isThinking;
}
