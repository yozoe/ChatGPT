// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class PluginAddMenuRow extends StatelessWidget {
  const PluginAddMenuRow({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Row(
      children: [
        Icon(icon, size: 23),
        const SizedBox(width: 13),
        Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
