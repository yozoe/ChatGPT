import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 将 Codex Desk 的 Keychain 数据保存到专属服务，并按需迁移旧的通用服务数据。
/// Stores Codex Desk Keychain data in a dedicated service and migrates legacy shared-service data on demand.
class CodexKeychainStorage {
  /// 创建专属安全存储；测试可注入存储实现。
  /// Creates dedicated secure storage; tests may inject storage implementations.
  CodexKeychainStorage({
    FlutterSecureStorage? storage,
    FlutterSecureStorage? legacyStorage,
  }) : _storage = storage ?? _dedicatedStorage,
       _legacyStorage = legacyStorage ?? storage ?? _legacySharedStorage;

  static const _dedicatedStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'com.yozoe.chatgpt.secure-storage',
      usesDataProtectionKeychain: false,
    ),
  );
  static const _legacySharedStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  final FlutterSecureStorage _storage;
  final FlutterSecureStorage _legacyStorage;

  /// 读取专属服务的值；首次缺失时从旧服务迁移并保留原始值。
  /// Reads a dedicated-service value; when absent, migrates it from the legacy service while retaining the original value.
  Future<String?> read({required String key}) async {
    final current = await _storage.read(key: key);
    if (current != null) return current;
    final legacy = await _legacyStorage.read(key: key);
    if (legacy == null) return null;
    await _storage.write(key: key, value: legacy);
    return legacy;
  }

  /// 将值写入 Codex Desk 专属 Keychain 服务。
  /// Writes a value to the dedicated Codex Desk Keychain service.
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  /// 从专属服务与旧服务删除值，避免用户清除设置后旧值再次迁移回来。
  /// Deletes a value from both dedicated and legacy services so cleared settings cannot be migrated back.
  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
    await _legacyStorage.delete(key: key);
  }
}
