import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 将本机 Codex Desk 偏好保存到项目目录之外。
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

  /// 读取用户覆盖的 Codex 可执行文件路径。
  /// Reads the user-overridden Codex executable path.
  Future<String?> readExecutable() => _storage.read(key: _executableKey);

  /// 保存用户选择的 Codex 可执行文件路径。
  /// Saves the user-selected Codex executable path.
  Future<void> saveExecutable(String executable) {
    return _storage.write(key: _executableKey, value: executable);
  }

  /// 删除已保存的可执行文件路径，恢复自动发现。
  /// Deletes the saved executable path and restores automatic discovery.
  Future<void> clear() => _storage.delete(key: _executableKey);

  /// 读取上次成功选择的本地项目路径。
  /// Reads the last successfully selected local workspace path.
  Future<String?> readWorkspace() => _storage.read(key: _workspaceKey);

  /// 保存最近选择的本地项目路径。
  /// Saves the most recently selected local workspace path.
  Future<void> saveWorkspace(String workspace) {
    return _storage.write(key: _workspaceKey, value: workspace);
  }

  /// 清除失效或不再使用的本地项目路径。
  /// Clears an invalid or no-longer-used local workspace path.
  Future<void> clearWorkspace() => _storage.delete(key: _workspaceKey);

  /// 读取用户保存的推理强度标识。
  /// Reads the user's saved reasoning-effort identifier.
  Future<String?> readReasoningEffort() =>
      _storage.read(key: _reasoningEffortKey);

  /// 保存推理强度；传入 `null` 时清除用户偏好。
  /// Saves reasoning effort; passing `null` clears the user preference.
  Future<void> saveReasoningEffort(String? effort) {
    if (effort == null) return _storage.delete(key: _reasoningEffortKey);
    return _storage.write(key: _reasoningEffortKey, value: effort);
  }
}
