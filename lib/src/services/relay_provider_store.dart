import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/relay_provider_configuration.dart';

/// Persists relay settings in the OS secure store (macOS Keychain), never in
/// project files, App Server config, or application logs.
class RelayProviderStore {
  RelayProviderStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _baseUrlKey = 'codex_desk.relay.base_url';
  static const _modelKey = 'codex_desk.relay.model';
  static const _apiKeyKey = 'codex_desk.relay.api_key';

  final FlutterSecureStorage _storage;

  Future<RelayProviderConfiguration?> read() async {
    final values = await Future.wait([
      _storage.read(key: _baseUrlKey),
      _storage.read(key: _modelKey),
      _storage.read(key: _apiKeyKey),
    ]);
    final baseUrl = values[0];
    final model = values[1];
    final apiKey = values[2];
    if (baseUrl == null || model == null || apiKey == null) return null;
    if (baseUrl.isEmpty || model.isEmpty || apiKey.isEmpty) return null;
    return RelayProviderConfiguration(
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
  }

  Future<void> save(RelayProviderConfiguration configuration) async {
    await Future.wait([
      _storage.write(key: _baseUrlKey, value: configuration.baseUrl),
      _storage.write(key: _modelKey, value: configuration.model),
      _storage.write(key: _apiKeyKey, value: configuration.apiKey),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _baseUrlKey),
      _storage.delete(key: _modelKey),
      _storage.delete(key: _apiKeyKey),
    ]);
  }
}
