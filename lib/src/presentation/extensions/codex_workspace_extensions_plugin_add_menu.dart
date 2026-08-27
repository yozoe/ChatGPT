// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugin_add_menu_row.dart';

class PluginAddMenu extends StatelessWidget {
  const PluginAddMenu({
    required this.onCreatePlugin,
    required this.onAddMarketplace,
    required this.onRecordSkill,
  });

  final VoidCallback onCreatePlugin;
  final Future<void> Function() onAddMarketplace;
  final VoidCallback onRecordSkill;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return PopupMenuButton<PluginAddAction>(
      key: const Key('plugins-add-menu'),
      tooltip: '添加',
      color: palette.module,
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border),
      ),
      onSelected: (action) {
        switch (action) {
          case PluginAddAction.createPlugin:
            onCreatePlugin();
          case PluginAddAction.addMarketplace:
            unawaited(onAddMarketplace());
          case PluginAddAction.recordSkill:
            onRecordSkill();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: PluginAddAction.createPlugin,
          child: PluginAddMenuRow(
            icon: Icons.extension_outlined,
            label: '创建插件',
          ),
        ),
        PopupMenuItem(
          value: PluginAddAction.addMarketplace,
          child: PluginAddMenuRow(icon: Icons.add, label: '添加插件市场'),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: PluginAddAction.recordSkill,
          child: PluginAddMenuRow(
            icon: Icons.radio_button_unchecked,
            label: '录制技能',
          ),
        ),
      ],
      child: FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('添加'),
      ),
    );
  }
}
