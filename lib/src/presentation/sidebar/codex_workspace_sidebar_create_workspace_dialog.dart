// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_create_workspace_dialog_state.dart';

/// Codex 风格的创建项目弹窗，支持选择或拖入一个主目录及多个附加目录。
/// Codex-style project creation dialog accepting one primary folder and
/// multiple additional folders from the native picker or desktop drop.
class CreateWorkspaceDialog extends StatefulWidget {
  const CreateWorkspaceDialog({required this.onCreate});

  final Future<bool> Function(List<String> paths, String name) onCreate;

  @override
  State<CreateWorkspaceDialog> createState() => CreateWorkspaceDialogState();
}
