// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class WorkspaceDetailsRow extends StatelessWidget {
  const WorkspaceDetailsRow({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
