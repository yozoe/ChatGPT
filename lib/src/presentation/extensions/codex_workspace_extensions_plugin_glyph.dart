// Extracted class from codex_workspace_extensions.dart.
import 'package:flutter_svg/flutter_svg.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_plugin_mark.dart';

class PluginGlyph extends StatelessWidget {
  const PluginGlyph({
    super.key,
    required this.name,
    required this.active,
    this.logoPath,
  });
  final String name;
  final bool active;
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final hue = name.hashCode.abs() % 360;
    final fallbackColor = active ? palette.trace : palette.muted;
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HSVColor.fromAHSV(
          1,
          hue.toDouble(),
          .58,
          .8,
        ).toColor().withValues(alpha: .18),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: active ? palette.active : palette.border),
      ),
      child: logoPath == null
          ? _fallbackIcon(fallbackColor)
          : ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _logo(fallbackColor),
            ),
    );
  }

  Widget _logo(Color fallbackColor) {
    final file = File(logoPath!);
    if (file.path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        file,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackIcon(fallbackColor),
      );
    }
    return Image.file(
      file,
      width: 46,
      height: 46,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _fallbackIcon(fallbackColor),
    );
  }

  Widget _fallbackIcon(Color color) => buildCodexPluginMark(color: color);
}
