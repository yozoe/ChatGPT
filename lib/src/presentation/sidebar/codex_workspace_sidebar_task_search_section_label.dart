// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class TaskSearchSectionLabel extends StatelessWidget {
  const TaskSearchSectionLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: YeknomPalette.of(context).muted,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
