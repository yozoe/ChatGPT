// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_git_project_dialog_state.dart';

class GitProjectDialog extends StatefulWidget {
  const GitProjectDialog({super.key, required this.controller});

  final CodexController controller;

  @override
  State<GitProjectDialog> createState() => GitProjectDialogState();
}
