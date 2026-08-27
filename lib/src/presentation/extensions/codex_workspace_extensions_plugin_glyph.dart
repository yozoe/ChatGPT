// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';

class PluginGlyph extends StatelessWidget {
  const PluginGlyph({required this.name, required this.active});
  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final hue = name.hashCode.abs() % 360;
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
      child: Icon(
        Icons.extension_outlined,
        color: HSVColor.fromAHSV(1, hue.toDouble(), .58, .96).toColor(),
      ),
    );
  }
}
