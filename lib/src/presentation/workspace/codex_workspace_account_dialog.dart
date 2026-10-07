import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_account_dialog_state.dart';

class CodexWorkspaceAccountDialog extends StatefulWidget {
  const CodexWorkspaceAccountDialog({super.key, this.overrideController});

  final CodexController? overrideController;

  @override
  State<CodexWorkspaceAccountDialog> createState() =>
      CodexWorkspaceAccountDialogState();
}
