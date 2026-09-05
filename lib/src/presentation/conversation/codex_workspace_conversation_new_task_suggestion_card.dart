import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_new_task_suggestion_card_state.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

/// One keyboard-accessible prompt starter on the new-task welcome surface.
class NewTaskSuggestionCard extends StatefulWidget {
  const NewTaskSuggestionCard({
    required this.width,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final double width;
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onPressed;

  @override
  State<NewTaskSuggestionCard> createState() => NewTaskSuggestionCardState();
}
