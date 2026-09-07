// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class SkillScopeLabel extends StatelessWidget {
  const SkillScopeLabel({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 10, bottom: 4),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}
