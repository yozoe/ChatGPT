import 'dart:convert';
import 'dart:math';

import 'package:chatgpt/src/domain/browser_download_record.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';
import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;

/// Persists download metadata without taking ownership of downloaded files.
class BrowserDownloadStore {
  BrowserDownloadStore({CodexKeychainStorage? storage})
    : _storage = storage ?? CodexKeychainStorage();

  static const _key = 'codex_desk.browser.downloads.v1';
  static const _encryptionKey = 'codex_desk.history.encryption_key.v1';
  static const _maxEntries = 200;

  final CodexKeychainStorage _storage;

  Future<List<BrowserDownloadRecord>> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null || stored.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(await _decrypt(stored));
      if (decoded is! List) return const [];
      return decoded
          .map((value) {
            try {
              return BrowserDownloadRecord.fromJson(value);
            } on FormatException {
              return null;
            }
          })
          .whereType<BrowserDownloadRecord>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on Object {
      return const [];
    }
  }

  Future<void> record({
    required Uri url,
    required String filePath,
    DateTime? downloadedAt,
  }) async {
    if ((url.scheme != 'http' && url.scheme != 'https') ||
        url.host.trim().isEmpty ||
        filePath.trim().isEmpty) {
      return;
    }
    final existing = await read();
    final fileName = filePath.split(RegExp(r'[/\\]')).last;
    final next = <BrowserDownloadRecord>[
      BrowserDownloadRecord(
        url: Uri(
          scheme: url.scheme,
          host: url.host,
          port: url.hasPort ? url.port : null,
          path: url.path,
        ).toString(),
        filePath: filePath,
        fileName: fileName,
        downloadedAt: (downloadedAt ?? DateTime.now()).toUtc(),
      ),
      ...existing.where((record) => record.filePath != filePath),
    ];
    await _write(next.take(_maxEntries));
  }

  Future<void> remove(String filePath) async {
    final entries = await read();
    await _write(entries.where((record) => record.filePath != filePath));
  }

  Future<void> clear() => _storage.delete(key: _key);

  Future<void> _write(Iterable<BrowserDownloadRecord> entries) async {
    final values = entries
        .map((entry) => entry.toJson())
        .toList(growable: false);
    if (values.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(key: _key, value: await _encrypt(jsonEncode(values)));
  }

  Future<String> _encrypt(String value) async {
    final algorithm = AesGcm.with256bits();
    final box = await algorithm.encrypt(
      utf8.encode(value),
      secretKey: SecretKey(await _readOrCreateEncryptionKey()),
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
    if (envelope is! Map ||
        envelope['nonce'] is! String ||
        envelope['mac'] is! String ||
        envelope['ciphertext'] is! String) {
      throw const FormatException('下载记录无法解密。');
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
    final stored = await _storage.read(key: _encryptionKey);
    if (stored != null && stored.isNotEmpty) return base64Decode(stored);
    final generated = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
    );
    await _storage.write(key: _encryptionKey, value: base64Encode(generated));
    return generated;
  }
}
