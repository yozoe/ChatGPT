import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_new_task_welcome_state.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

const String codexNewTaskMarkSvg = '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M22 12.5c4.2-3.2 10-3.5 14.5-.8a13.4 13.4 0 0 1 15.2 12.4 13.5 13.5 0 0 1-4.2 24.8 13.5 13.5 0 0 1-22.6 3.4A13.4 13.4 0 0 1 10.6 32 13.5 13.5 0 0 1 22 12.5Z" stroke="#888" stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="m21.5 29 4.5 4-4.5 4M34 38h7.5" stroke="#888" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

/// Codex-style invitation shown before a new task has its first user message.
class NewTaskWelcome extends StatefulWidget {
  const NewTaskWelcome({
    required this.bottomInset,
    required this.suggestionsVisible,
    required this.onExploreSelected,
    required this.onSuggestionSelected,
    super.key,
  });

  final double bottomInset;
  final bool suggestionsVisible;
  final VoidCallback onExploreSelected;
  final ValueChanged<String> onSuggestionSelected;

  @override
  State<NewTaskWelcome> createState() => NewTaskWelcomeState();
}
