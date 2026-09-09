import 'package:chatgpt/src/domain/timeline_entry.dart';

/// 创建使用同一时间戳边界的持久时间线条目，保证排序和恢复结果稳定。
/// Creates durable timeline entries with one consistent timestamp boundary.
class CodexTimelineEntryFactory {
  TimelineEntry create(
    TimelineKind kind,
    String title,
    String detail, {
    List<String> imagePaths = const [],
    String? sourceItemId,
    String? activityKind,
    String? activityStatus,
    String? agentPhase,
    String? linkedThreadId,
    String? activityPrompt,
    String? activityParentThreadId,
  }) {
    return TimelineEntry(
      kind: kind,
      title: title,
      detail: detail,
      createdAt: DateTime.now(),
      imagePaths: imagePaths,
      sourceItemId: sourceItemId,
      activityKind: activityKind,
      activityStatus: activityStatus,
      agentPhase: agentPhase,
      linkedThreadId: linkedThreadId,
      activityPrompt: activityPrompt,
      activityParentThreadId: activityParentThreadId,
    );
  }
}
