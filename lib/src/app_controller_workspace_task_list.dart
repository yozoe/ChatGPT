// Extracted class from app_controller.dart.
import 'package:chatgpt/src/domain/codex_thread.dart';

/// 非当前项目的只读任务清单，来自本地历史而非活动运行时。
/// Read-only task list for an inactive workspace, sourced from local history.
class WorkspaceTaskList {
  const WorkspaceTaskList({
    required this.threads,
    required this.pinnedIds,
    required this.acknowledgedIds,
  });

  final List<CodexThread> threads;
  final Set<String> pinnedIds;
  final Set<String> acknowledgedIds;
}
