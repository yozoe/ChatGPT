// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class LibraryTabButton extends StatelessWidget {
  const LibraryTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Material(
      color: selected ? palette.raised : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? palette.trace : palette.muted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
