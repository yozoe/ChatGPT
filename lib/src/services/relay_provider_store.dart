import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/relay_provider_configuration.dart';

/// Persists relay settings in the OS secure store (macOS Keychain), never in
/// project files, App Server config, or application logs.
class RelayProviderStore {
  RelayProviderStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _configurationKey = 'codex_desk.relay.configuration.v1';
  static const _legacyBaseUrlKey = 'codex_desk.relay.base_url';
  static const _legacyModelKey = 'codex_desk.relay.model';
  static const _legacyApiKeyKey = 'codex_desk.relay.api_key';

  final FlutterSecureStorage _storage;

  Future<RelayProviderConfiguration?> read() async {
    final encoded = await _storage.read(key: _configurationKey);
    if (encoded != null) return _decode(encoded);

    final values = await Future.wait([
      _storage.read(key: _legacyBaseUrlKey),
      _storage.read(key: _legacyModelKey),
      _storage.read(key: _legacyApiKeyKey),
    ]);
    final baseUrl = values[0];
    final model = values[1];
    final apiKey = values[2];
    if (baseUrl == null || model == null || apiKey == null) return null;
    if (baseUrl.isEmpty || model.isEmpty || apiKey.isEmpty) return null;
    final legacy = RelayProviderConfiguration(
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
    await save(legacy);
    await _deleteLegacyKeys();
    return legacy;
  }

  Future<void> save(RelayProviderConfiguration configuration) async {
    final encoded = jsonEncode({
      'baseUrl': configuration.baseUrl,
      'model': configuration.model,
      'apiKey': configuration.apiKey,
    });
    await _storage.write(key: _configurationKey, value: encoded);
  }

  Future<void> clear() async {
    await _deleteLegacyKeys();
    await _storage.delete(key: _configurationKey);
  }

  RelayProviderConfiguration _decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Keychain 中的中转站配置格式无效。');
    }
    final baseUrl = decoded['baseUrl'];
    final model = decoded['model'];
    final apiKey = decoded['apiKey'];
    if (baseUrl is! String || model is! String || apiKey is! String) {
      throw const FormatException('Keychain 中的中转站配置不完整。');
    }
    final normalizedBaseUrl = RelayProviderConfiguration.normalizeBaseUrl(
      baseUrl,
    );
    if (model.trim().isEmpty || apiKey.isEmpty) {
      throw const FormatException('Keychain 中的中转站配置不完整。');
    }
    return RelayProviderConfiguration(
      baseUrl: normalizedBaseUrl,
      model: model.trim(),
      apiKey: apiKey,
    );
  }

  Future<void> _deleteLegacyKeys() {
    return Future.wait([
      _storage.delete(key: _legacyBaseUrlKey),
      _storage.delete(key: _legacyModelKey),
      _storage.delete(key: _legacyApiKeyKey),
    ]);
  }
}
