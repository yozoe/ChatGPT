import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chatgpt/src/domain/browser_tab_snapshot.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';
import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;

/// Persists opt-in browser tabs without storing page contents or credentials.
class BrowserSessionStore {
  BrowserSessionStore({CodexKeychainStorage? storage})
    : _storage = storage ?? CodexKeychainStorage();

  static const _key = 'codex_desk.browser.session.v1';
  static const _encryptionKey = 'codex_desk.history.encryption_key.v1';

  final CodexKeychainStorage _storage;
  Future<void> _mutationQueue = Future<void>.value();

  Future<({List<BrowserTabSnapshot> tabs, int activeIndex})?> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null || stored.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(await _decrypt(stored));
      if (decoded is! Map || decoded['tabs'] is! List) return null;
      final tabs = (decoded['tabs'] as List)
          .map((value) {
            try {
              return BrowserTabSnapshot.fromJson(value);
            } on FormatException {
              return null;
            }
          })
          .whereType<BrowserTabSnapshot>()
          .toList(growable: false);
      if (tabs.isEmpty) return null;
      final active = decoded['activeIndex'];
      final activeIndex = active is int ? active.clamp(0, tabs.length - 1) : 0;
      return (tabs: tabs, activeIndex: activeIndex);
    } on FormatException {
      return null;
    } on Object {
      return null;
    }
  }

  Future<void> save({
    required List<BrowserTabSnapshot> tabs,
    required int activeIndex,
  }) async {
    final valid = tabs
        .where(
          (tab) =>
              (tab.url.startsWith('http://') || tab.url.startsWith('https://')),
        )
        .map(
          (tab) => BrowserTabSnapshot(
            url: Uri.tryParse(tab.url)?.replace(userInfo: '').toString() ?? '',
            title: tab.title,
          ),
        )
        .where((tab) => tab.url.isNotEmpty)
        .take(20)
        .toList(growable: false);
    await _enqueue(() async {
      if (valid.isEmpty) {
        await _storage.delete(key: _key);
        return;
      }
      final value = jsonEncode({
        'version': 1,
        'tabs': valid.map((tab) => tab.toJson()).toList(growable: false),
        'activeIndex': activeIndex.clamp(0, valid.length - 1),
      });
      await _storage.write(key: _key, value: await _encrypt(value));
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

  Future<String> _encrypt(String value) async {
    final box = await AesGcm.with256bits().encrypt(
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
      throw const FormatException('浏览器标签快照无法解密。');
    }
    final box = SecretBox(
      base64Decode(envelope['ciphertext'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );
    return utf8.decode(
      await AesGcm.with256bits().decrypt(
        box,
        secretKey: SecretKey(await _readOrCreateEncryptionKey()),
      ),
    );
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
