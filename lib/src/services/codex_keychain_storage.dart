import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_storage_scope.dart';

/// 将 Codex Desk 偏好和加密密钥保存到应用专用的本地文件。
/// Stores Codex Desk preferences and encryption keys in an app-specific local file.
///
/// The class name is retained for source compatibility with existing callers.
class CodexKeychainStorage {
  CodexKeychainStorage({Directory? developmentDirectory})
    : _developmentDirectory = developmentDirectory,
      _legacyMigrationEnabled = kReleaseMode && developmentDirectory == null;

  final Directory? _developmentDirectory;
  final bool _legacyMigrationEnabled;
  Future<void>? _legacyMigrationFuture;

  static const _migrationMarker =
      '__codex_desk.keychain_migration.completed.v1';
  static const _legacyKeys = <String>[
    'codex_desk.history.encryption_key.v1',
    'codex_desk.runtime.executable.v1',
    'codex_desk.workspace.last_path.v1',
    'codex_desk.workspace.additional_paths.v1',
    'codex_desk.workspaces.v2',
    'codex_desk.workspaces.pinned.v1',
    'codex_desk.reasoning_effort.v1',
    'codex_desk.model.selected.v1',
    'codex_desk.approval_mode.v1',
    'codex_desk.scheduled_tasks.v1',
  ];
  static const _legacyDedicatedStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'com.yozoe.chatgpt.secure-storage',
      usesDataProtectionKeychain: false,
    ),
  );
  static const _legacySharedStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static Future<void> _storageMutations = Future<void>.value();

  /// Reads a value from the local storage file.
  Future<String?> read({required String key}) async {
    var values = await _readValues();
    if (_legacyMigrationEnabled && values[_migrationMarker] == null) {
      await _ensureLegacyMigration();
      values = await _readValues();
    }
    return values[key];
  }

  /// Writes a value to the local storage file.
  Future<void> write({required String key, required String value}) {
    return _mutateValues((values) => values[key] = value);
  }

  /// Deletes a value from the local storage file.
  Future<void> delete({required String key}) async {
    await _mutateValues((values) => values.remove(key));
  }

  /// Malformed data fails rather than being silently overwritten.
  Future<Map<String, String>> _readValues() async {
    final file = _storageFile();
    if (!await file.exists()) return <String, String>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map || decoded['values'] is! Map) {
      throw const FormatException('本地存储格式无效。');
    }
    return (decoded['values'] as Map).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  Future<void> _ensureLegacyMigration() {
    final existing = _legacyMigrationFuture;
    if (existing != null) return existing;
    final migration = _migrateLegacyValues().catchError((_) {});
    _legacyMigrationFuture = migration;
    return migration;
  }

  /// Performs the one-time upgrade from the old Release Keychain service.
  /// Existing installs may show one authorization prompt during this upgrade;
  /// successful completion records a marker so later launches stay local-only.
  Future<void> _migrateLegacyValues() async {
    final values = await _readValues();
    if (values[_migrationMarker] != null) return;
    var migrationStatus = 'completed';
    for (final key in _legacyKeys) {
      if (values.containsKey(key)) continue;
      try {
        final legacy =
            await _legacyDedicatedStorage.read(key: key) ??
            await _legacySharedStorage.read(key: key);
        if (legacy != null) values[key] = legacy;
      } catch (_) {
        // A denied or unavailable Keychain should not make local storage
        // unusable or cause an authorization prompt on every read.
        migrationStatus = 'skipped';
        break;
      }
    }
    values[_migrationMarker] = migrationStatus;
    await _writeValues(values);
  }

  /// 串行化读取—修改—写入序列，防止并发偏好更新互相覆盖。
  /// Serializes read-modify-write operations so concurrent preferences cannot overwrite each other.
  Future<void> _mutateValues(
    void Function(Map<String, String> values) mutation,
  ) {
    final result = _storageMutations.then((_) async {
      final values = await _readValues();
      mutation(values);
      await _writeValues(values);
    });
    _storageMutations = result.catchError((Object _) {});
    return result;
  }

  Future<void> _writeValues(Map<String, String> values) async {
    final file = _storageFile();
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

  File _storageFile() {
    final directory =
        _developmentDirectory ?? AppStorageScope.defaultDirectory();
    // Keep the existing filename so current local preferences survive the
    // storage backend change.
    return File('${directory.path}/development-storage-v1.json');
  }
}
