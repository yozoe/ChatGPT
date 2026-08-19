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

  /// Kept in memory only long enough to launch the local App Server process.
  /// Never include this value in logs, widgets, timeline entries, or config.
  final String apiKey;

  Map<String, String> get processEnvironment => {environmentVariable: apiKey};

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
