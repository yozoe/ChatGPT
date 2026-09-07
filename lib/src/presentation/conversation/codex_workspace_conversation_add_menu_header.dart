// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_header_state.dart';

class AddMenuHeader extends PopupMenuEntry<AddMenuAction> {
  const AddMenuHeader({super.key, required this.label, required this.palette});

  final String label;
  final YeknomPalette palette;

  @override
  double get height => 34;

  @override
  bool represents(AddMenuAction? value) => false;

  @override
  State<AddMenuHeader> createState() => AddMenuHeaderState();
}
