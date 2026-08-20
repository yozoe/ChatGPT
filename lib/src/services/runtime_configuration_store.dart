import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores a user-selected Codex CLI path. The path is kept outside projects so
/// opening a workspace never writes setup metadata into that repository.
class RuntimeConfigurationStore {
  RuntimeConfigurationStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const _executableKey = 'codex_desk.runtime.executable.v1';

  final FlutterSecureStorage _storage;

  Future<String?> readExecutable() => _storage.read(key: _executableKey);

  Future<void> saveExecutable(String executable) {
    return _storage.write(key: _executableKey, value: executable);
  }

  Future<void> clear() => _storage.delete(key: _executableKey);
}
