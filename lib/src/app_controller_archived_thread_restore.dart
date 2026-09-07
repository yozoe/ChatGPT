// Extracted class from app_controller.dart.
import 'package:chatgpt/src/domain/codex_thread.dart';

/// 保存“先取消归档、再打开任务”的可重试上下文。
/// Retry context for unarchiving a task before opening it.
class ArchivedThreadRestore {
  const ArchivedThreadRestore({required this.workspace, required this.thread});
  final String workspace;
  final CodexThread thread;
}
