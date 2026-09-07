// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_editable_task_title_state.dart';

class EditableTaskTitle extends StatefulWidget {
  const EditableTaskTitle({super.key, required this.controller});

  final CodexController controller;

  @override
  State<EditableTaskTitle> createState() => EditableTaskTitleState();
}
