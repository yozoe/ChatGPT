import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_dialog.dart';

class SettingsPluginsSection extends StatelessWidget {
  const SettingsPluginsSection({
    super.key,
    required this.controller,
    required this.onAddMarketplace,
    required this.onManageMarketplaces,
  });

  final CodexController controller;
  final Future<void> Function() onAddMarketplace;
  final Future<void> Function() onManageMarketplaces;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 620 ? 24.0 : 72.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            46,
            horizontalPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '插件',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 38,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '管理已安装插件、MCP 服务器和可用技能。',
                style: TextStyle(color: YeknomPalette.of(context).muted),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ExtensionSettingsDialog(
                  embedded: true,
                  controller: controller,
                  onAddMarketplace: onAddMarketplace,
                  onManageMarketplaces: onManageMarketplaces,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
