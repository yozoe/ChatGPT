// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ExtensionSkillGlyph extends StatelessWidget {
  const ExtensionSkillGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.border),
      ),
      child: Icon(Icons.layers_outlined, size: 18, color: palette.muted),
    );
  }
}
