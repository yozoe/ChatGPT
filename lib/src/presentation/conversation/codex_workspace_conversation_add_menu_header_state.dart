// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_header.dart';

class AddMenuHeaderState extends State<AddMenuHeader> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        widget.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: widget.palette.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
