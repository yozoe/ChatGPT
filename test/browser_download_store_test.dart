import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/services/browser_download_store.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';

void main() {
  late Directory directory;
  late BrowserDownloadStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('browser-download-store-');
    store = BrowserDownloadStore(
      storage: CodexKeychainStorage(developmentDirectory: directory),
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('stores download metadata without exposing query parameters', () async {
    await store.record(
      url: Uri.parse('https://user:secret@example.com/file?token=secret'),
      filePath: '${directory.path}/report.txt',
    );

    final records = await store.read();
    expect(records.single.url, 'https://example.com/file');
    expect(records.single.fileName, 'report.txt');
    final raw = await File(
      '${directory.path}/development-storage-v1.json',
    ).readAsString();
    expect(raw, isNot(contains('token=secret')));
    expect(raw, isNot(contains('secret')));
  });

  test('clearing metadata does not delete the downloaded file', () async {
    final file = File('${directory.path}/saved.txt')..writeAsStringSync('data');
    await store.record(
      url: Uri.parse('https://example.com/file'),
      filePath: file.path,
    );
    await store.clear();

    expect(await store.read(), isEmpty);
    expect(await file.exists(), isTrue);
  });
}
