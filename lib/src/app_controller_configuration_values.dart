/// Extracts non-sensitive display values from resolved Codex configuration.
class CodexConfigurationValues {
  String? nonEmptyString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? originLabel(Object? rawOrigins, String field) {
    if (rawOrigins is! Map) return null;
    Object? metadata = rawOrigins[field];
    if (metadata == null) {
      for (final entry in rawOrigins.entries) {
        final key = entry.key.toString();
        if (key == field ||
            key.endsWith('/$field') ||
            key.endsWith('.$field')) {
          metadata = entry.value;
          break;
        }
      }
    }
    if (metadata is! Map || metadata['name'] is! Map) return null;
    final source = metadata['name'] as Map;
    final type = source['type']?.toString();
    return switch (type) {
      'user' => nonEmptyString(source['file']) ?? '用户配置',
      'project' => switch (nonEmptyString(source['dotCodexFolder'])) {
        final folder? => '$folder/config.toml',
        null => '项目配置',
      },
      'system' || 'legacyManagedConfigTomlFromFile' =>
        nonEmptyString(source['file']) ?? '系统配置',
      'packagedDefaults' => 'Codex 内置默认值',
      'sessionFlags' => '运行时启动参数',
      'mdm' => '设备管理配置',
      'enterpriseManaged' => nonEmptyString(source['name']) ?? '组织管理配置',
      'legacyManagedConfigTomlFromMdm' => '设备管理配置',
      _ => null,
    };
  }
}
