// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_result.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_dialog_state.dart';

class TaskSearchDialog extends StatefulWidget {
  const TaskSearchDialog({
    super.key,
    required this.results,
    required this.canCreateTask,
    required this.canOpenTask,
    required this.canSearchFiles,
    required this.onOpenTask,
    required this.onNewTask,
    required this.onOpenWorkspace,
    required this.onSearchFiles,
  });

  final List<TaskSearchResult> results;
  final bool canCreateTask;
  final bool Function(TaskSearchResult result) canOpenTask;
  final bool canSearchFiles;
  final Future<void> Function(TaskSearchResult result) onOpenTask;
  final VoidCallback onNewTask;
  final VoidCallback onOpenWorkspace;
  final Future<void> Function() onSearchFiles;

  @override
  State<TaskSearchDialog> createState() => TaskSearchDialogState();
}
