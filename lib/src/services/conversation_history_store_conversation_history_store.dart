// Extracted class from conversation_history_store.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey, Sha256;
import 'app_storage_scope.dart';
import 'codex_keychain_storage.dart';
import 'conversation_history_store_conversation_history_snapshot.dart';

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
  final Map<String, ConversationHistorySnapshot> _memorySnapshots = {};

  /// 读取指定工作区的历史快照；没有缓存时返回 `null`。
  /// Reads the history snapshot for a workspace and returns `null` when absent.
  Future<ConversationHistorySnapshot?> read(String workspace) async {
    final cached = _memorySnapshots[workspace];
    if (cached != null) return cached;
    final projectFile = await _projectFile(workspace);
    if (await projectFile.exists()) {
      final clearText = await _decrypt(await projectFile.readAsString());
      final decoded = await Isolate.run(() => jsonDecode(clearText));
      if (decoded is! Map || decoded['snapshot'] is! Map) {
        throw const FormatException('本地项目历史记录格式无效。');
      }
      final storedWorkspace = decoded['workspace']?.toString();
      if (storedWorkspace != null && storedWorkspace != workspace) {
        throw const FormatException('本地项目历史记录归属无效。');
      }
      final rawSnapshot = decoded['snapshot'] as Map;
      final snapshot = await Isolate.run(
        () => ConversationHistorySnapshot.fromJson(rawSnapshot),
      );
      _memorySnapshots[workspace] = snapshot;
      return snapshot;
    }

    // Older releases kept all projects in one encrypted JSON document. Read
    // it only as a compatibility path, then migrate this project in the
    // background so future switches do not decode unrelated histories.
    final legacyFile = await _legacyFile();
    if (!await legacyFile.exists()) return null;
    final legacyText = await _decrypt(await legacyFile.readAsString());
    final decoded = await Isolate.run(() => jsonDecode(legacyText));
    if (decoded is! Map || decoded['workspaces'] is! Map) {
      throw const FormatException('本地历史记录格式无效。');
    }
    final rawSnapshot = (decoded['workspaces'] as Map)[workspace];
    if (rawSnapshot is! Map) return null;
    final snapshot = await Isolate.run(
      () => ConversationHistorySnapshot.fromJson(rawSnapshot),
    );
    _memorySnapshots[workspace] = snapshot;
    unawaited(
      save(workspace: workspace, snapshot: snapshot).onError((_, _) {}),
    );
    return snapshot;
  }

  /// 串行且原子地保存指定工作区的历史快照，并保留其他工作区的缓存。
  /// Serializes and atomically saves a workspace snapshot while retaining the other workspace caches.
  Future<void> save({
    required String workspace,
    required ConversationHistorySnapshot snapshot,
  }) async {
    // Make a just-captured snapshot immediately available to project switching;
    // durable writes remain serialized in the background.
    _memorySnapshots[workspace] = snapshot;
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
    final file = await _projectFile(workspace);
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.${Random.secure().nextInt(1 << 32)}.tmp',
    );
    final clearText = await Isolate.run(
      () => jsonEncode({
        'version': 2,
        'workspace': workspace,
        'snapshot': snapshot.toJson(),
      }),
    );
    await temporary.writeAsString(await _encrypt(clearText), flush: true);
    await temporary.rename(file.path);
  }

  /// 使用本地存储的密钥将明文封装为 AES-GCM JSON。
  /// Encrypts plaintext into an AES-GCM JSON envelope using the local key.
  Future<String> _encrypt(String value) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(await _readOrCreateEncryptionKey());
    final box = await algorithm.encrypt(
      utf8.encode(value),
      secretKey: secretKey,
    );
    return Isolate.run(
      () => jsonEncode({
        'version': 1,
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'ciphertext': base64Encode(box.cipherText),
      }),
    );
  }

  /// 解密 AES-GCM 缓存，并兼容读取首版的明文缓存。
  /// Decrypts the AES-GCM cache and remains compatible with the first plaintext format.
  Future<String> _decrypt(String encoded) async {
    final envelope = await Isolate.run(() => jsonDecode(encoded));
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

  /// 从本地存储读取 256 位密钥，不存在时安全生成并保存。
  /// Reads the 256-bit key from local storage, generating and storing it when absent.
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

  /// Returns the legacy all-project cache used only for migration.
  Future<File> _legacyFile() async {
    final directory = _directory ?? _defaultDirectory();
    return File('${directory.path}/conversation-history-v1.json');
  }

  /// Returns a collision-resistant cache file dedicated to one project.
  Future<File> _projectFile(String workspace) async {
    final directory = _directory ?? _defaultDirectory();
    final digest = await Sha256().hash(utf8.encode(workspace));
    final fileName = base64UrlEncode(digest.bytes).replaceAll('=', '');
    return File('${directory.path}/conversation-history-v2/$fileName.json');
  }

  /// 解析 macOS Application Support 中的默认缓存目录。
  /// Resolves the default cache directory in macOS Application Support.
  Directory _defaultDirectory() {
    return AppStorageScope.defaultDirectory();
  }
}
