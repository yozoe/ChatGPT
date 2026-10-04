import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;
import 'package:chatgpt/src/domain/browser_history_entry.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';

/// Persists browser history separately from conversation history and downloads.
class BrowserHistoryStore {
  BrowserHistoryStore({CodexKeychainStorage? storage})
    : _storage = storage ?? CodexKeychainStorage();

  static const _key = 'codex_desk.browser.history.v1';
  static const _encryptionKey = 'codex_desk.history.encryption_key.v1';
  static const _maxEntries = 200;

  final CodexKeychainStorage _storage;
  Future<void> _mutationQueue = Future<void>.value();

  Future<List<BrowserHistoryEntry>> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null || stored.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(await _decrypt(stored));
      if (decoded is! List) return const [];
      return decoded
          .map((value) {
            try {
              return BrowserHistoryEntry.fromJson(value);
            } on FormatException {
              return null;
            }
          })
          .whereType<BrowserHistoryEntry>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on Object {
      return const [];
    }
  }

  Future<void> record({
    required Uri uri,
    String? title,
    DateTime? visitedAt,
  }) async {
    final canonical = _canonicalUri(uri);
    if (canonical == null) return;
    await _enqueue(() async {
      final existing = await read();
      final entries = <BrowserHistoryEntry>[
        BrowserHistoryEntry(
          url: canonical.toString(),
          title: title?.trim().isNotEmpty == true
              ? title!.trim()
              : canonical.host,
          visitedAt: (visitedAt ?? DateTime.now()).toUtc(),
        ),
        ...existing.where((entry) => entry.url != canonical.toString()),
      ];
      await _write(entries.take(_maxEntries));
    });
  }

  Future<void> remove(String url) async {
    await _enqueue(() async {
      final entries = await read();
      await _write(entries.where((entry) => entry.url != url));
    });
  }

  Future<void> clear() => _enqueue(() => _storage.delete(key: _key));

  Future<void> _enqueue(Future<void> Function() action) async {
    final previous = _mutationQueue;
    final done = Completer<void>();
    _mutationQueue = done.future;
    await previous.catchError((_) {});
    try {
      await action();
    } finally {
      done.complete();
    }
  }

  Uri? _canonicalUri(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.trim().isEmpty) {
      return null;
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
  }

  Future<void> _write(Iterable<BrowserHistoryEntry> entries) async {
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
      throw const FormatException('浏览历史无法解密。');
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
