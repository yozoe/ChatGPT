// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';

class AddMenuMessage extends PopupMenuItem<AddMenuAction> {
  AddMenuMessage({required String label, super.key})
    : super(
        enabled: false,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label),
      );
}
