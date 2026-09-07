// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_add_mcp_server_dialog_state.dart';

class AddMcpServerDialog extends StatefulWidget {
  const AddMcpServerDialog({super.key, required this.controller});
  final CodexController controller;

  @override
  State<AddMcpServerDialog> createState() => AddMcpServerDialogState();
}
