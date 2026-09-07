// Extracted class from app_controller.dart.
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'app_controller_support.dart';

/// 因另一 Codex 客户端仍持有线程 writer 而被拒绝的可恢复操作；同时保留
/// 原工作区，避免用户切换项目后执行过期重试。
/// A recoverable operation rejected because another Codex client still owns
/// the thread writer. The original workspace is retained so a stale retry can
/// never run after the user moves to another project.
class ThreadWriterConflict {
  const ThreadWriterConflict({
    required this.workspace,
    required this.threads,
    required this.operation,
  });

  final String workspace;
  final List<CodexThread> threads;
  final ThreadWriterConflictOperation operation;
}
