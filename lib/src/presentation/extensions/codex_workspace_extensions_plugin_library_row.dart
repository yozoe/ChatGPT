// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugin_glyph.dart';

class PluginLibraryRow extends StatelessWidget {
  const PluginLibraryRow({
    required this.plugin,
    required this.busy,
    required this.onInstall,
  });
  final CodexPlugin plugin;
  final bool busy;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          PluginGlyph(
            name: plugin.title,
            active: plugin.installed && plugin.enabled,
            logoPath: plugin.logoPath,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  plugin.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted),
                ),
              ],
            ),
          ),
          if (plugin.installed)
            const Icon(Icons.more_horiz, size: 20)
          else
            OutlinedButton(
              onPressed: busy ? null : onInstall,
              child: const Text('安装'),
            ),
        ],
      ),
    );
  }
}
