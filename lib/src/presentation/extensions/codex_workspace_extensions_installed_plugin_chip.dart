// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugin_glyph.dart';

class InstalledPluginChip extends StatelessWidget {
  const InstalledPluginChip({super.key, required this.plugin});
  final CodexPlugin plugin;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    child: Column(
      children: [
        PluginGlyph(
          name: plugin.title,
          active: plugin.enabled,
          logoPath: plugin.logoPath,
        ),
        const SizedBox(height: 7),
        Text(
          plugin.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
