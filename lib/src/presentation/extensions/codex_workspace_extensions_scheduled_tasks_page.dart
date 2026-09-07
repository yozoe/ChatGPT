// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_tasks_page_state.dart';

class ScheduledTasksPage extends StatefulWidget {
  const ScheduledTasksPage({
    super.key,
    required this.controller,
    required this.onCreate,
  });

  final CodexController controller;
  final Future<void> Function([String? initialPrompt]) onCreate;

  @override
  State<ScheduledTasksPage> createState() => ScheduledTasksPageState();
}
