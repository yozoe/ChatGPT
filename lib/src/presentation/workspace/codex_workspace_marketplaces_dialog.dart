import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_marketplace_tile.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_controller_builder.dart';

class CodexWorkspaceMarketplacesDialog extends StatelessWidget {
  const CodexWorkspaceMarketplacesDialog({
    super.key,
    this.overrideController,
    required this.onRemove,
  });

  final CodexController? overrideController;
  final Future<void> Function(CodexMarketplace marketplace) onRemove;

  @override
  Widget build(BuildContext context) {
    return ControllerBuilder(
      overrideController: overrideController,
      builder: (context, controller) {
        final error = controller.marketplacesError;
        return AlertDialog(
          title: const Text('插件市场'),
          content: SizedBox(
            width: 640,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (controller.pluginSaving) const LinearProgressIndicator(),
                if (controller.pluginActionProgress case final progress?) ...[
                  const SizedBox(height: 10),
                  Text(progress, key: const Key('marketplace-action-progress')),
                ],
                if (controller.pluginsError case final actionError?) ...[
                  const SizedBox(height: 10),
                  Text(
                    actionError,
                    style: TextStyle(color: YeknomPalette.of(context).fault),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: controller.marketplacesLoading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                      ? Center(child: Text(error))
                      : controller.marketplaces.isEmpty
                      ? const Center(child: Text('尚未配置插件市场。'))
                      : ListView.separated(
                          itemCount: controller.marketplaces.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final marketplace = controller.marketplaces[index];
                            return MarketplaceTile(
                              marketplace: marketplace,
                              busy: controller.pluginSaving,
                              onUpgrade: () => controller
                                  .upgradePluginMarketplace(marketplace.name),
                              onRemove: () => onRemove(marketplace),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: controller.pluginSaving
                  ? null
                  : () => controller.upgradePluginMarketplace(null),
              icon: const Icon(Icons.system_update_outlined),
              label: const Text('刷新所有 Git 市场'),
            ),
            TextButton.icon(
              onPressed:
                  controller.marketplacesLoading || controller.pluginSaving
                  ? null
                  : controller.refreshMarketplaces,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
