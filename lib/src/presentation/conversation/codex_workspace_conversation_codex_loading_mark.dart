// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class CodexLoadingMark extends StatelessWidget {
  const CodexLoadingMark({super.key});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/codex-desk-icon-traced-leaves.png',
    width: 62,
    height: 62,
    fit: BoxFit.contain,
  );
}
