import 'dart:io';

import 'package:chatgpt/src/services/codex_keychain_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'codex-desk-development-storage-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists values locally without using Keychain', () async {
    final first = CodexKeychainStorage(
      developmentDirectory: temporaryDirectory,
    );
    await first.write(key: 'workspace', value: '/tmp/project');

    final second = CodexKeychainStorage(
      developmentDirectory: temporaryDirectory,
    );
    expect(await second.read(key: 'workspace'), '/tmp/project');

    await second.delete(key: 'workspace');
    expect(await first.read(key: 'workspace'), isNull);
  });
}
