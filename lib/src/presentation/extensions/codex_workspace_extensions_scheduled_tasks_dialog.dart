// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_tasks_dialog_state.dart';

class ScheduledTasksDialog extends StatefulWidget {
  const ScheduledTasksDialog({
    super.key,
    required this.controller,
    this.initialPrompt,
    this.initialRunAt,
  });

  final CodexController controller;
  final String? initialPrompt;
  final DateTime? initialRunAt;

  @override
  State<ScheduledTasksDialog> createState() => ScheduledTasksDialogState();
}
