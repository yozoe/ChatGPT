// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class TaskSearchResult {
  const TaskSearchResult({
    required this.thread,
    required this.workspacePath,
    required this.workspaceName,
  });

  final CodexThread thread;
  final String workspacePath;
  final String workspaceName;

  String get providerLabel => thread.modelProvider?.trim().isNotEmpty == true
      ? thread.modelProvider!.trim()
      : 'Codex';
}
