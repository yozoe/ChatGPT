import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores local Codex Desk preferences outside user projects.
class RuntimeConfigurationStore {
  RuntimeConfigurationStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const _executableKey = 'codex_desk.runtime.executable.v1';
  static const _workspaceKey = 'codex_desk.workspace.last_path.v1';
  static const _reasoningEffortKey = 'codex_desk.reasoning_effort.v1';

  final FlutterSecureStorage _storage;

  Future<String?> readExecutable() => _storage.read(key: _executableKey);

  Future<void> saveExecutable(String executable) {
    return _storage.write(key: _executableKey, value: executable);
  }

  Future<void> clear() => _storage.delete(key: _executableKey);

  Future<String?> readWorkspace() => _storage.read(key: _workspaceKey);

  Future<void> saveWorkspace(String workspace) {
    return _storage.write(key: _workspaceKey, value: workspace);
  }

  Future<void> clearWorkspace() => _storage.delete(key: _workspaceKey);

  Future<String?> readReasoningEffort() =>
      _storage.read(key: _reasoningEffortKey);

  Future<void> saveReasoningEffort(String? effort) {
    if (effort == null) return _storage.delete(key: _reasoningEffortKey);
    return _storage.write(key: _reasoningEffortKey, value: effort);
  }
}
