import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/codex_file_change.dart';
import '../domain/codex_thread.dart';
import '../domain/timeline_entry.dart';

class ConversationHistorySnapshot {
  const ConversationHistorySnapshot({
    required this.threads,
    required this.archivedThreads,
    required this.entries,
    required this.fileChanges,
    this.turnDiff,
  });

  final List<CodexThread> threads;
  final List<CodexThread> archivedThreads;
  final List<TimelineEntry> entries;
  final List<CodexFileChange> fileChanges;
  final String? turnDiff;

  Map<String, dynamic> toJson() => {
    'threads': threads.map((thread) => thread.toJson()).toList(),
    'archivedThreads': archivedThreads
        .map((thread) => thread.toJson())
        .toList(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'fileChanges': fileChanges.map((change) => change.toJson()).toList(),
    'turnDiff': ?turnDiff,
  };

  factory ConversationHistorySnapshot.fromJson(Map<dynamic, dynamic> value) {
    List<T> decodeList<T>(
      Object? raw,
      T Function(Map<dynamic, dynamic>) parse,
    ) {
      if (raw is! Iterable) return const [];
      return raw.whereType<Map>().map(parse).toList(growable: false);
    }

    return ConversationHistorySnapshot(
      threads: decodeList(
        value['threads'],
        (thread) => CodexThread.fromJson(Map<String, dynamic>.from(thread)),
      ),
      archivedThreads: decodeList(
        value['archivedThreads'],
        (thread) => CodexThread.fromJson(Map<String, dynamic>.from(thread)),
      ),
      entries: decodeList(value['entries'], TimelineEntry.fromJson),
      fileChanges: decodeList(value['fileChanges'], CodexFileChange.fromJson),
      turnDiff: value['turnDiff']?.toString(),
    );
  }
}

/// Stores a per-workspace conversation cache in the user's Application Support
/// folder. This cache allows history to remain visible while App Server is
/// stopped or temporarily unavailable.
class ConversationHistoryStore {
  ConversationHistoryStore({
    Directory? directory,
    FlutterSecureStorage? secureStorage,
  }) : _directory = directory,
       _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           );

  static const _encryptionKey = 'codex_desk.history.encryption_key.v1';
  final Directory? _directory;
  final FlutterSecureStorage _secureStorage;

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

  Future<void> save({
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
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['workspaces'] is Map) {
        content = Map<String, dynamic>.from(decoded);
        content['workspaces'] = Map<String, dynamic>.from(
          decoded['workspaces'] as Map,
        );
      }
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

  Future<File> _file() async {
    final directory = _directory ?? _defaultDirectory();
    return File('${directory.path}/conversation-history-v1.json');
  }

  Directory _defaultDirectory() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('无法确定 macOS 用户目录。');
    }
    return Directory('$home/Library/Application Support/Codex Desk');
  }
}
