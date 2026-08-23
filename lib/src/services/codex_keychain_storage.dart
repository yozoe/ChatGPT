import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

import 'app_storage_scope.dart';

/// Release builds use a dedicated Keychain service; development builds use an isolated file store.
class CodexKeychainStorage {
  /// Creates build-appropriate storage; tests may inject either implementation.
  CodexKeychainStorage({
    FlutterSecureStorage? storage,
    FlutterSecureStorage? legacyStorage,
    bool? useDevelopmentStorage,
    Directory? developmentDirectory,
  }) : _storage = storage ?? _dedicatedStorage,
       _legacyStorage = legacyStorage ?? storage ?? _legacySharedStorage,
       _useDevelopmentStorage =
           useDevelopmentStorage ??
           (storage == null && legacyStorage == null && !kReleaseMode),
       _developmentDirectory = developmentDirectory;

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
  final bool _useDevelopmentStorage;
  final Directory? _developmentDirectory;

  static Future<void> _developmentMutations = Future<void>.value();

  /// 读取专属服务的值；首次缺失时从旧服务迁移并保留原始值。
  /// Reads a dedicated-service value; when absent, migrates it from the legacy service while retaining the original value.
  Future<String?> read({required String key}) async {
    if (_useDevelopmentStorage) {
      return (await _readDevelopmentValues())[key];
    }
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
    if (_useDevelopmentStorage) {
      return _mutateDevelopmentValues((values) => values[key] = value);
    }
    return _storage.write(key: key, value: value);
  }

  /// 从专属服务与旧服务删除值，避免用户清除设置后旧值再次迁移回来。
  /// Deletes a value from both dedicated and legacy services so cleared settings cannot be migrated back.
  Future<void> delete({required String key}) async {
    if (_useDevelopmentStorage) {
      await _mutateDevelopmentValues((values) => values.remove(key));
      return;
    }
    await _storage.delete(key: key);
    await _legacyStorage.delete(key: key);
  }

  Future<Map<String, String>> _readDevelopmentValues() async {
    final file = _developmentFile();
    if (!await file.exists()) return <String, String>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map || decoded['values'] is! Map) {
      throw const FormatException('开发存储格式无效。');
    }
    return (decoded['values'] as Map).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  Future<void> _mutateDevelopmentValues(
    void Function(Map<String, String> values) mutation,
  ) {
    final result = _developmentMutations.then((_) async {
      final values = await _readDevelopmentValues();
      mutation(values);
      await _writeDevelopmentValues(values);
    });
    _developmentMutations = result.catchError((Object _) {});
    return result;
  }

  Future<void> _writeDevelopmentValues(Map<String, String> values) async {
    final file = _developmentFile();
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(
        jsonEncode({'version': 1, 'values': values}),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  File _developmentFile() {
    final directory =
        _developmentDirectory ?? AppStorageScope.defaultDirectory();
    return File('${directory.path}/development-storage-v1.json');
  }
}
