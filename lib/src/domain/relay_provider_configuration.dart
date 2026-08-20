class RelayProviderConfiguration {
  const RelayProviderConfiguration({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  static const providerId = 'codex_desk_relay';
  static const environmentVariable = 'CODEX_DESK_RELAY_API_KEY';

  final String baseUrl;
  final String model;

  /// 仅在启动本地 App Server 所需的短时间内保存在内存中，绝不可写入日志、Widget、时间线或配置。
  /// Kept in memory only long enough to launch the local App Server process; never include it in logs, widgets, timeline entries, or config.
  final String apiKey;

  /// 返回仅供本地 App Server 子进程使用的密钥环境变量。
  /// Returns the secret environment variable used only by the local App Server process.
  Map<String, String> get processEnvironment => {environmentVariable: apiKey};

  /// 返回创建或恢复中转站线程时需要的 App Server 配置。
  /// Returns App Server configuration required when creating or resuming relay threads.
  Map<String, dynamic> get threadConfig => {
    'model_providers': {
      providerId: {
        'name': 'Codex Desk Relay',
        'base_url': baseUrl,
        'env_key': environmentVariable,
        'wire_api': 'responses',
      },
    },
  };

  /// 返回替换可选 Provider 字段后的配置副本。
  /// Returns a configuration copy with optional provider fields replaced.
  RelayProviderConfiguration copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    return RelayProviderConfiguration(
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  /// 验证并规范化中转站 Base URL，仅允许 HTTPS 或本机 HTTP。
  /// Validates and normalizes a relay Base URL, allowing HTTPS or local HTTP only.
  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('请输入有效的 Provider Base URL。');
    }
    final isLocalHttp =
        uri.scheme == 'http' &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1');
    if (uri.scheme != 'https' && !isLocalHttp) {
      throw const FormatException('中转站必须使用 HTTPS；仅 localhost 可使用 HTTP。');
    }
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      throw const FormatException('Base URL 不能包含查询参数或片段。');
    }
    return trimmed;
  }
}
