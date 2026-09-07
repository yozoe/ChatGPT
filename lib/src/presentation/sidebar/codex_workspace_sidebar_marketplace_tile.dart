// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class MarketplaceTile extends StatelessWidget {
  const MarketplaceTile({
    super.key,
    required this.marketplace,
    required this.busy,
    required this.onUpgrade,
    required this.onRemove,
  });

  final CodexMarketplace marketplace;
  final bool busy;
  final VoidCallback onUpgrade;
  final VoidCallback onRemove;

  /// 构建 marketplace 行；只为 Git 来源提供刷新操作。
  /// Builds the marketplace row and exposes refresh only for Git sources.
  @override
  Widget build(BuildContext context) {
    final source = marketplace.source?.isNotEmpty == true
        ? marketplace.source!
        : marketplace.root;
    return ListTile(
      leading: const Icon(Icons.storefront_outlined),
      title: Text(marketplace.name),
      subtitle: Text(
        '${marketplace.sourceTypeLabel} · $source',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (marketplace.sourceType == 'git')
            IconButton(
              tooltip: '刷新 Git 市场',
              onPressed: busy ? null : onUpgrade,
              icon: const Icon(Icons.system_update_outlined),
            ),
          IconButton(
            tooltip: '移除插件市场',
            onPressed: busy ? null : onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
