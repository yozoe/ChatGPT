/// 描述当前 Codex CLI 已配置的一个插件 marketplace。
/// Describes one plugin marketplace configured in the current Codex CLI.
class CodexMarketplace {
  /// 创建 marketplace 领域对象。
  /// Creates a marketplace domain object.
  const CodexMarketplace({
    required this.name,
    required this.root,
    this.sourceType,
    this.source,
  });

  final String name;
  final String root;
  final String? sourceType;
  final String? source;

  /// 返回来源类型的本地化展示文本。
  /// Returns a localized display label for the source type.
  String get sourceTypeLabel => switch (sourceType) {
    'git' => 'Git 仓库',
    'local' => '本地目录',
    _ => 'Codex 管理',
  };

  /// 从 Codex CLI JSON 映射读取 marketplace。
  /// Reads a marketplace from a Codex CLI JSON mapping.
  static CodexMarketplace? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    if (name.isEmpty) return null;
    final source = json['marketplaceSource'];
    return CodexMarketplace(
      name: name,
      root: json['root']?.toString() ?? '',
      sourceType: source is Map ? source['sourceType']?.toString() : null,
      source: source is Map ? source['source']?.toString() : null,
    );
  }
}
