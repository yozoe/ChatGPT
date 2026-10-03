import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/domain/browser_history_entry.dart';
import 'package:chatgpt/src/services/browser_history_store.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';

void main() {
  late Directory directory;
  late BrowserHistoryStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('browser-history-');
    store = BrowserHistoryStore(
      storage: CodexKeychainStorage(developmentDirectory: directory),
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('stores canonical web URLs without query or fragment', () async {
    await store.record(
      uri: Uri.parse('https://user:secret@example.com/docs?token=secret#part'),
      title: 'Docs',
      visitedAt: DateTime.utc(2026, 1, 2),
    );

    final entries = await store.read();
    expect(entries, hasLength(1));
    expect(entries.single.url, 'https://example.com/docs');
    expect(entries.single.title, 'Docs');
    final raw = await File(
      '${directory.path}/development-storage-v1.json',
    ).readAsString();
    expect(raw, isNot(contains('example.com/docs')));
    expect(raw, isNot(contains('secret')));
  });

  test('moves repeated URLs to the front and supports deletion', () async {
    await store.record(uri: Uri.parse('https://example.com/one'));
    await store.record(uri: Uri.parse('https://example.com/two'));
    await store.record(uri: Uri.parse('https://example.com/one?new=1'));

    expect((await store.read()).map((entry) => entry.url), [
      'https://example.com/one',
      'https://example.com/two',
    ]);
    await store.remove('https://example.com/one');
    expect((await store.read()).map((entry) => entry.url), [
      'https://example.com/two',
    ]);
  });

  test('ignores non-web URLs', () async {
    await store.record(uri: Uri.parse('mailto:user@example.com'));
    expect(await store.read(), isEmpty);
  });

  test('decodes persisted entries with UTC timestamps', () {
    final entry = BrowserHistoryEntry(
      url: 'https://example.com',
      title: 'Example',
      visitedAt: DateTime.utc(2026, 1, 2),
    );
    expect(
      BrowserHistoryEntry.fromJson(entry.toJson()).visitedAt.isUtc,
      isTrue,
    );
  });
}
