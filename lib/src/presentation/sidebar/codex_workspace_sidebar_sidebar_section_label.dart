// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class SidebarSectionLabel extends StatelessWidget {
  const SidebarSectionLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: palette.faint,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
      ),
    );
  }
}
