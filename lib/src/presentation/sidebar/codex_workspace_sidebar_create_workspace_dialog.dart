// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_create_workspace_dialog_state.dart';

/// Codex 风格的创建项目弹窗，源文件夹为可选项。
/// Codex-style project creation dialog with optional source folders.
class CreateWorkspaceDialog extends StatefulWidget {
  const CreateWorkspaceDialog({super.key, required this.onCreate});

  final Future<bool> Function(List<String> paths, String name) onCreate;

  @override
  State<CreateWorkspaceDialog> createState() => CreateWorkspaceDialogState();
}
