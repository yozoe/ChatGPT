// Extracted class from app_controller.dart.
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';

/// 已打开任务的内存视图缓存。
/// In-memory view state for a previously opened task.
class ThreadViewSnapshot {
  const ThreadViewSnapshot({
    required this.entries,
    required this.fileChanges,
    required this.turnDiff,
  });

  final List<TimelineEntry> entries;
  final List<CodexFileChange> fileChanges;
  final String? turnDiff;
}
