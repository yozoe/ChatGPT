// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ScheduledTaskSuggestion {
  const ScheduledTaskSuggestion({
    required this.icon,
    required this.color,
    required this.title,
    required this.schedule,
    required this.prompt,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String schedule;
  final String prompt;
}
