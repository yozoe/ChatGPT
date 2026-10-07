import 'dart:io';

import 'package:chatgpt/src/domain/browser_download_record.dart';
import 'package:chatgpt/src/domain/browser_history_entry.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_clear_data_dialog.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_download_records_dialog.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_history_dialog.dart';
import 'package:chatgpt/src/services/browser_download_store.dart';
import 'package:chatgpt/src/services/browser_history_store.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('filters browser history and opens the selected URL', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('browser-dialogs-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = BrowserHistoryStore(
      storage: CodexKeychainStorage(developmentDirectory: directory),
    );
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => BrowserHistoryDialog(
                entries: [
                  BrowserHistoryEntry(
                    url: 'https://example.com/docs',
                    title: 'Example Docs',
                    visitedAt: DateTime.utc(2026),
                  ),
                  BrowserHistoryEntry(
                    url: 'https://flutter.dev',
                    title: 'Flutter',
                    visitedAt: DateTime.utc(2026),
                  ),
                ],
                store: store,
                onOpen: (value) => opened = value,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('browser-history-search')),
      'flutter',
    );
    await tester.pump();

    expect(find.text('Flutter'), findsOneWidget);
    expect(find.text('Example Docs'), findsNothing);
    await tester.tap(find.text('Flutter'));
    await tester.pumpAndSettle();
    expect(opened, Uri.parse('https://flutter.dev'));
  });

  testWidgets('returns only the selected browser data domains', (tester) async {
    Set<String>? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selection = await showDialog<Set<String>>(
                context: context,
                builder: (context) => const BrowserClearDataDialog(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('browser-clear-cache')));
    await tester.tap(find.byKey(const Key('browser-clear-download-data')));
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(selection, {'website', 'history'});
  });

  testWidgets(
    'removes download metadata without touching the dialog contract',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('browser-dialogs-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = BrowserDownloadStore(
        storage: CodexKeychainStorage(developmentDirectory: directory),
      );
      final records = [
        BrowserDownloadRecord(
          url: 'https://example.com/file',
          filePath: '/tmp/file.txt',
          fileName: 'file.txt',
          downloadedAt: DateTime.utc(2026),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => BrowserDownloadRecordsDialog(
                  records: records,
                  store: store,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      expect(records, hasLength(1));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('file.txt'), findsOneWidget);
      await tester.tap(find.byTooltip('删除记录（不删除文件）'));
      await tester.pump();
    },
  );
}
