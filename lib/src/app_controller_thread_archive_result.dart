// Extracted class from app_controller.dart.

/// 单次归档提交结果，同时保留因状态变化而未发送请求的任务及原因。
/// Result of one archive submission, including tasks deliberately left
/// untouched because their state changed before the request was sent.
class ThreadArchiveResult {
  ThreadArchiveResult({
    Iterable<String> archivedIds = const [],
    Iterable<String> runningThreadIds = const [],
    Iterable<String> updatingThreadIds = const [],
    Iterable<String> unavailableThreadIds = const [],
  }) : archivedIds = Set.unmodifiable(archivedIds),
       runningThreadIds = Set.unmodifiable(runningThreadIds),
       updatingThreadIds = Set.unmodifiable(updatingThreadIds),
       unavailableThreadIds = Set.unmodifiable(unavailableThreadIds);

  final Set<String> archivedIds;
  final Set<String> runningThreadIds;
  final Set<String> updatingThreadIds;
  final Set<String> unavailableThreadIds;
}
