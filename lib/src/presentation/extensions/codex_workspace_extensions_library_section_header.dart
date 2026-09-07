// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class LibrarySectionHeader extends StatelessWidget {
  const LibrarySectionHeader({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 10, bottom: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
