import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;
import '../domain/codex_file_change.dart';
import '../domain/codex_thread.dart';
import '../domain/timeline_entry.dart';
import 'app_storage_scope.dart';
import 'codex_keychain_storage.dart';

class ConversationHistorySnapshot {
  const ConversationHistorySnapshot({
    required this.threads,
    required this.archivedThreads,
    required this.entries,
    required this.fileChanges,
    this.pinnedThreadIds = const {},
    this.turnDiff,
    this.activeThreadId,
    this.ownedThreadIds = const {},
    this.historyInitialized = false,
  });

  final List<CodexThread> threads;
  final List<CodexThread> archivedThreads;
  final List<TimelineEntry> entries;
  final List<CodexFileChange> fileChanges;
  final Set<String> pinnedThreadIds;
  final String? turnDiff;

  /// The thread that was open when the workspace snapshot was saved.
  /// 保存快照时当前打开的线程；旧版本快照没有此字段时保持为空。
  final String? activeThreadId;

  /// Thread IDs explicitly belonging to this project.
  final Set<String> ownedThreadIds;

  /// Whether the project has established its thread boundary.
  final bool historyInitialized;

  /// 将当前工作区快照转换为可持久化的 JSON。
  /// Converts the current workspace snapshot to persistable JSON.
  Map<String, dynamic> toJson() => {
    'threads': threads.map((thread) => thread.toJson()).toList(),
    'archivedThreads': archivedThreads
        .map((thread) => thread.toJson())
        .toList(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'fileChanges': fileChanges.map((change) => change.toJson()).toList(),
    'pinnedThreadIds': pinnedThreadIds.toList(growable: false),
    'turnDiff': ?turnDiff,
    'activeThreadId': ?activeThreadId,
    'ownedThreadIds': ownedThreadIds.toList(growable: false),
    'historyInitialized': historyInitialized,
  };

  /// 从持久化 JSON 恢复当前工作区快照。
  /// Restores a workspace snapshot from persisted JSON.
  factory ConversationHistorySnapshot.fromJson(Map<dynamic, dynamic> value) {
    /// 过滤无效元素并按调用方指定的解析函数恢复列表。
    /// Filters invalid elements and restores a list with the supplied parser.
    List<T> decodeList<T>(
      Object? raw,
      T Function(Map<dynamic, dynamic>) parse,
    ) {
      if (raw is! Iterable) return const [];
      return raw.whereType<Map>().map(parse).toList(growable: false);
    }

    final decodedThreads = decodeList(
      value['threads'],
      (thread) => CodexThread.fromJson(Map<String, dynamic>.from(thread)),
    );
    final decodedArchivedThreads = decodeList(
      value['archivedThreads'],
      (thread) => CodexThread.fromJson(Map<String, dynamic>.from(thread)),
    );
    final explicitOwned = value['ownedThreadIds'] is Iterable
        ? (value['ownedThreadIds'] as Iterable)
              .where((id) => id != null)
              .map((id) => id.toString().trim())
              .where((id) => id.isNotEmpty)
              .toSet()
        : <String>{};
    // Older snapshots did not have an ownership field; their visible threads
    // are the safest migration source.
    final owned = <String>{
      ...explicitOwned,
      ...decodedThreads.map((thread) => thread.id),
      ...decodedArchivedThreads.map((thread) => thread.id),
    };
    return ConversationHistorySnapshot(
      threads: decodedThreads,
      archivedThreads: decodedArchivedThreads,
      entries: decodeList(value['entries'], TimelineEntry.fromJson),
      fileChanges: decodeList(value['fileChanges'], CodexFileChange.fromJson),
      pinnedThreadIds: value['pinnedThreadIds'] is Iterable
          ? (value['pinnedThreadIds'] as Iterable)
                .where((id) => id != null)
                .map((id) => id.toString())
                .where((id) => id.isNotEmpty)
                .toSet()
          : const {},
      turnDiff: value['turnDiff']?.toString(),
      activeThreadId: value['activeThreadId']?.toString().trim().isEmpty == true
          ? null
          : value['activeThreadId']?.toString(),
      ownedThreadIds: owned,
      historyInitialized:
          value['historyInitialized'] == true || owned.isNotEmpty,
    );
  }
}

/// 可移植的本地历史导出格式；只包含本应用的缓存，不代表可恢复 App Server 的原始 session。
/// A portable local-history export format; it includes only this app's cache and cannot restore an App Server session.
class PortableConversationHistory {
  const PortableConversationHistory({
    required this.workspace,
    required this.exportedAt,
    required this.snapshot,
  });

  static const schemaVersion = 1;

  final String workspace;
  final DateTime exportedAt;
  final ConversationHistorySnapshot snapshot;

  /// 将可移植历史转换为包含版本和来源项目的 JSON。
  /// Converts portable history to JSON containing its version and source workspace.
  Map<String, dynamic> toJson() => {
    'format': 'codex-desk-history',
    'version': schemaVersion,
    'workspace': workspace,
    'exportedAt': exportedAt.toIso8601String(),
    'snapshot': snapshot.toJson(),
  };

  /// 验证并解析由 Codex Desk 导出的可移植历史 JSON。
  /// Validates and parses portable-history JSON exported by Codex Desk.
  factory PortableConversationHistory.fromJson(Map<dynamic, dynamic> value) {
    if (value['format'] != 'codex-desk-history' ||
        value['version'] != schemaVersion ||
        value['snapshot'] is! Map) {
      throw const FormatException('不是受支持的 Codex Desk 历史导出文件。');
    }
    return PortableConversationHistory(
      workspace: value['workspace']?.toString() ?? '',
      exportedAt:
          DateTime.tryParse(value['exportedAt']?.toString() ?? '') ??
          DateTime.now(),
      snapshot: ConversationHistorySnapshot.fromJson(value['snapshot'] as Map),
    );
  }
}

/// 将每个工作区的对话缓存加密保存到用户的 Application Support 目录，App Server 停止或暂时不可用时仍可显示历史。
/// Stores each workspace's encrypted conversation cache in Application Support so history remains visible while App Server is stopped or unavailable.
class ConversationHistoryStore {
  ConversationHistoryStore({
    Directory? directory,
    CodexKeychainStorage? secureStorage,
  }) : _directory = directory,
       _secureStorage = secureStorage ?? CodexKeychainStorage();

  static const _encryptionKey = 'codex_desk.history.encryption_key.v1';
  final Directory? _directory;
  final CodexKeychainStorage _secureStorage;
  Future<void> _saveQueue = Future<void>.value();

  /// 读取指定工作区的历史快照；没有缓存时返回 `null`。
  /// Reads the history snapshot for a workspace and returns `null` when absent.
  Future<ConversationHistorySnapshot?> read(String workspace) async {
    final file = await _file();
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await _decrypt(await file.readAsString()));
    if (decoded is! Map || decoded['workspaces'] is! Map) {
      throw const FormatException('本地历史记录格式无效。');
    }
    final snapshot = (decoded['workspaces'] as Map)[workspace];
    return snapshot is Map
        ? ConversationHistorySnapshot.fromJson(snapshot)
        : null;
  }

  /// 串行且原子地保存指定工作区的历史快照，并保留其他工作区的缓存。
  /// Serializes and atomically saves a workspace snapshot while retaining the other workspace caches.
  Future<void> save({
    required String workspace,
    required ConversationHistorySnapshot snapshot,
  }) async {
    final previousSave = _saveQueue;
    final nextSave = () async {
      try {
        await previousSave;
      } catch (_) {
        // A failed older write must not prevent a later snapshot from being
        // persisted. The later write still validates its own input.
      }
      await _saveNow(workspace: workspace, snapshot: snapshot);
    }();
    _saveQueue = nextSave;
    await nextSave;
  }

  Future<void> _saveNow({
    required String workspace,
    required ConversationHistorySnapshot snapshot,
  }) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    Map<String, dynamic> content = {
      'version': 1,
      'workspaces': <String, dynamic>{},
    };
    if (await file.exists()) {
      // The on-disk value is normally an AES-GCM envelope. Decode the
      // plaintext before updating one workspace so existing encrypted entries
      // are retained instead of being silently replaced.
      final decoded = jsonDecode(await _decrypt(await file.readAsString()));
      if (decoded is! Map || decoded['workspaces'] is! Map) {
        throw const FormatException('本地历史记录格式无效。');
      }
      content = Map<String, dynamic>.from(decoded);
      content['workspaces'] = Map<String, dynamic>.from(
        decoded['workspaces'] as Map,
      );
    }
    (content['workspaces'] as Map<String, dynamic>)[workspace] = snapshot
        .toJson();
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.${Random.secure().nextInt(1 << 32)}.tmp',
    );
    await temporary.writeAsString(
      await _encrypt(jsonEncode(content)),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  /// 使用存储在 Keychain 中的密钥将明文封装为 AES-GCM JSON。
  /// Encrypts plaintext into an AES-GCM JSON envelope using the Keychain key.
  Future<String> _encrypt(String value) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(await _readOrCreateEncryptionKey());
    final box = await algorithm.encrypt(
      utf8.encode(value),
      secretKey: secretKey,
    );
    return jsonEncode({
      'version': 1,
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    });
  }

  /// 解密 AES-GCM 缓存，并兼容读取首版的明文缓存。
  /// Decrypts the AES-GCM cache and remains compatible with the first plaintext format.
  Future<String> _decrypt(String encoded) async {
    final envelope = jsonDecode(encoded);
    // The first cache release used plain JSON. Keep it readable so the next
    // successful save can migrate it to an encrypted envelope.
    if (envelope is Map && envelope['workspaces'] is Map) return encoded;
    if (envelope is! Map ||
        envelope['nonce'] is! String ||
        envelope['mac'] is! String ||
        envelope['ciphertext'] is! String) {
      throw const FormatException('本地历史记录无法解密。');
    }
    final box = SecretBox(
      base64Decode(envelope['ciphertext'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );
    final clearText = await AesGcm.with256bits().decrypt(
      box,
      secretKey: SecretKey(await _readOrCreateEncryptionKey()),
    );
    return utf8.decode(clearText);
  }

  /// 从 Keychain 读取 256 位密钥，不存在时安全生成并保存。
  /// Reads the 256-bit key from Keychain, generating and storing it when absent.
  Future<List<int>> _readOrCreateEncryptionKey() async {
    final stored = await _secureStorage.read(key: _encryptionKey);
    if (stored != null && stored.isNotEmpty) return base64Decode(stored);
    final random = Random.secure();
    final generated = List<int>.generate(32, (_) => random.nextInt(256));
    await _secureStorage.write(
      key: _encryptionKey,
      value: base64Encode(generated),
    );
    return generated;
  }

  /// 返回历史缓存文件的绝对路径对象。
  /// Returns the file object for the absolute history cache path.
  Future<File> _file() async {
    final directory = _directory ?? _defaultDirectory();
    return File('${directory.path}/conversation-history-v1.json');
  }

  /// 解析 macOS Application Support 中的默认缓存目录。
  /// Resolves the default cache directory in macOS Application Support.
  Directory _defaultDirectory() {
    return AppStorageScope.defaultDirectory();
  }
}
