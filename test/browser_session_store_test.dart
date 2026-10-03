import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/domain/browser_tab_snapshot.dart';
import 'package:chatgpt/src/services/browser_session_store.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';

void main() {
  late Directory directory;
  late BrowserSessionStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('browser-session-store-');
    store = BrowserSessionStore(
      storage: CodexKeychainStorage(developmentDirectory: directory),
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('round trips opted-in tab snapshots and active index', () async {
    await store.save(
      tabs: const [
        BrowserTabSnapshot(
          url: 'https://user:secret@example.com/one',
          title: 'One',
        ),
        BrowserTabSnapshot(url: 'https://example.com/two', title: 'Two'),
      ],
      activeIndex: 1,
    );

    final restored = await store.read();
    expect(restored?.activeIndex, 1);
    expect(restored?.tabs.map((tab) => tab.url), [
      'https://example.com/one',
      'https://example.com/two',
    ]);
    final raw = await File(
      '${directory.path}/development-storage-v1.json',
    ).readAsString();
    expect(raw, isNot(contains('example.com/one')));
    expect(raw, isNot(contains('secret')));
  });

  test('clearing the session removes only the persisted snapshot', () async {
    await store.save(
      tabs: const [
        BrowserTabSnapshot(url: 'https://example.com', title: 'Example'),
      ],
      activeIndex: 0,
    );
    await store.clear();
    expect(await store.read(), isNull);
  });
}
