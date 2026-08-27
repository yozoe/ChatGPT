// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';

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
