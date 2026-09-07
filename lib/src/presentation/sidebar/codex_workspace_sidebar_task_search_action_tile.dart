// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_shortcut.dart';

class TaskSearchActionTile extends StatelessWidget {
  const TaskSearchActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String shortcut;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled ? palette.trace : palette.faint,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? palette.trace : palette.faint,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TaskSearchShortcut(label: shortcut),
            ],
          ),
        ),
      ),
    );
  }
}
