/// 描述本机 Codex marketplace 中的一个插件及其安装状态。
/// Describes a plugin in the local Codex marketplace and its installation state.
class CodexPlugin {
  /// 创建插件领域对象。
  /// Creates a plugin domain object.
  const CodexPlugin({
    required this.id,
    required this.name,
    required this.marketplaceName,
    required this.installed,
    required this.enabled,
    this.version,
    this.installPolicy,
    this.authPolicy,
    this.description,
  });

  final String id;
  final String name;
  final String marketplaceName;
  final bool installed;
  final bool enabled;
  final String? version;
  final String? installPolicy;
  final String? authPolicy;
  final String? description;

  /// 返回适合在界面中展示的来源名称。
  /// Returns the source name suitable for UI display.
  String get sourceLabel =>
      marketplaceName.isEmpty ? '本地 marketplace' : marketplaceName;

  /// 返回插件连接器认证时机的本地化展示文本。
  /// Returns a localized label for the plugin connector authentication timing.
  String get authPolicyLabel => switch (authPolicy) {
    'ON_INSTALL' => '安装时可能请求连接',
    'ON_USE' => '首次使用时可能请求连接',
    _ => '无连接器认证信息',
  };

  /// 返回插件可否由当前用户安装的本地化展示文本。
  /// Returns a localized label for whether the current user may install the plugin.
  String get installPolicyLabel => switch (installPolicy) {
    'AVAILABLE' => '可安装',
    _ => '由 Codex 管理',
  };

  /// 使用新启用状态复制插件，保留其余 CLI 元数据。
  /// Copies the plugin with a new enabled state while retaining CLI metadata.
  CodexPlugin copyWith({bool? enabled}) => CodexPlugin(
    id: id,
    name: name,
    marketplaceName: marketplaceName,
    installed: installed,
    enabled: enabled ?? this.enabled,
    version: version,
    installPolicy: installPolicy,
    authPolicy: authPolicy,
    description: description,
  );

  /// 从 CLI JSON 映射读取插件；缺少必要字段时返回空值。
  /// Reads a plugin from CLI JSON and returns null when required fields are absent.
  static CodexPlugin? fromJson(Map<String, dynamic> json) {
    final id = json['pluginId']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    return CodexPlugin(
      id: id,
      name: name,
      marketplaceName: json['marketplaceName']?.toString() ?? '',
      installed: json['installed'] == true,
      enabled: json['enabled'] == true,
      version: json['version']?.toString(),
      installPolicy: json['installPolicy']?.toString(),
      authPolicy: json['authPolicy']?.toString(),
      description: json['description']?.toString(),
    );
  }
}
