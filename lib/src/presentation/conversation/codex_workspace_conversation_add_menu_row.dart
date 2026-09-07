// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class AddMenuRow extends StatelessWidget {
  const AddMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    this.description,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final titleColor = enabled ? palette.trace : palette.muted;
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.raised : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Icon(icon, size: 21, color: titleColor),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (description?.trim().isNotEmpty == true) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: palette.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, size: 17, color: palette.active),
            ],
          ],
        ),
      ),
    );
  }
}
