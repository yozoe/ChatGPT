import 'package:chatgpt/src/domain/timeline_entry.dart';

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
    );
  }
}
