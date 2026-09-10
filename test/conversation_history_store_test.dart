import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'codex-desk-conversation-history-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  ConversationHistoryStore createStore() => ConversationHistoryStore(
    directory: temporaryDirectory,
    secureStorage: CodexKeychainStorage(
      developmentDirectory: temporaryDirectory,
    ),
  );

  ConversationHistorySnapshot snapshot(String threadId) =>
      ConversationHistorySnapshot(
        threads: [
          CodexThread(
            id: threadId,
            preview: threadId,
            createdAt: 0,
            updatedAt: 0,
          ),
        ],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
      );

  test('retains encrypted histories for multiple projects', () async {
    final store = createStore();

    await store.save(workspace: 'project-a', snapshot: snapshot('thread-a'));
    await store.save(workspace: 'project-b', snapshot: snapshot('thread-b'));

    expect((await store.read('project-a'))!.threads.single.id, 'thread-a');
    expect((await store.read('project-b'))!.threads.single.id, 'thread-b');
    final projectFiles = Directory(
      '${temporaryDirectory.path}/conversation-history-v2',
    ).listSync();
    expect(projectFiles.whereType<File>(), hasLength(2));
    expect(
      File(
        '${temporaryDirectory.path}/conversation-history-v1.json',
      ).existsSync(),
      isFalse,
    );
  });

  test('migrates a legacy all-project snapshot on first read', () async {
    final legacySnapshot = snapshot('legacy-thread');
    await File(
      '${temporaryDirectory.path}/conversation-history-v1.json',
    ).writeAsString(
      jsonEncode({
        'version': 1,
        'workspaces': {'legacy-project': legacySnapshot.toJson()},
      }),
    );
    final store = createStore();

    final restored = await store.read('legacy-project');
    await store.save(workspace: 'legacy-project', snapshot: restored!);

    expect(restored.threads.single.id, 'legacy-thread');
    expect(
      Directory(
        '${temporaryDirectory.path}/conversation-history-v2',
      ).listSync().whereType<File>(),
      hasLength(1),
    );
  });

  test('serializes concurrent project history saves', () async {
    final store = createStore();

    await Future.wait([
      store.save(workspace: 'project-a', snapshot: snapshot('thread-a')),
      store.save(workspace: 'project-b', snapshot: snapshot('thread-b')),
    ]);

    expect((await store.read('project-a'))!.threads.single.id, 'thread-a');
    expect((await store.read('project-b'))!.threads.single.id, 'thread-b');
  });

  test('persists acknowledged completed-task reminders', () async {
    final store = createStore();
    final value = ConversationHistorySnapshot(
      threads: const [],
      archivedThreads: const [],
      entries: const [],
      fileChanges: const [],
      acknowledgedCompletedThreadIds: const {'completed-thread'},
    );

    await store.save(workspace: 'project-a', snapshot: value);

    expect((await store.read('project-a'))!.acknowledgedCompletedThreadIds, {
      'completed-thread',
    });
  });

  test('persists per-thread local image metadata', () async {
    final store = createStore();
    final entry = TimelineEntry(
      kind: TimelineKind.user,
      title: '你',
      detail: '请检查截图',
      createdAt: DateTime(2026),
      imagePaths: const ['/application-support/conversation-images/image.png'],
    );
    final value = ConversationHistorySnapshot(
      threads: const [],
      archivedThreads: const [],
      entries: const [],
      fileChanges: const [],
      userMessageEntriesByThreadId: {
        'inactive-thread': [entry],
      },
    );

    await store.save(workspace: 'project-a', snapshot: value);

    expect(
      (await store.read(
        'project-a',
      ))!.userMessageEntriesByThreadId['inactive-thread']!.single.imagePaths,
      entry.imagePaths,
    );
  });

  test('round-trips per-thread file summaries and diffs', () async {
    final store = createStore();
    final value = ConversationHistorySnapshot(
      threads: const [],
      archivedThreads: const [],
      entries: const [],
      fileChanges: const [],
      fileChangesByThreadId: {
        'thread-a': const [
          CodexFileChange(path: 'lib/a.dart', kind: 'modified', diff: '+a'),
        ],
        'thread-b': const [
          CodexFileChange(path: 'README.md', kind: 'added', diff: '+docs'),
        ],
      },
      turnDiffByThreadId: const {
        'thread-a': 'diff --git a/lib/a.dart b/lib/a.dart',
        'thread-b': null,
      },
    );

    await store.save(workspace: 'project-a', snapshot: value);
    final restored = await store.read('project-a');

    expect(
      restored!.fileChangesByThreadId['thread-a']!.single.path,
      'lib/a.dart',
    );
    expect(restored.fileChangesByThreadId['thread-b']!.single.kind, 'added');
    expect(restored.turnDiffByThreadId['thread-a'], contains('lib/a.dart'));
    expect(restored.turnDiffByThreadId['thread-b'], isNull);
  });

  test('restored local message metadata remains appendable', () async {
    final store = createStore();
    final entry = TimelineEntry(
      kind: TimelineKind.user,
      title: '你',
      detail: '第一条消息',
      createdAt: DateTime(2026),
    );
    await store.save(
      workspace: 'project-a',
      snapshot: ConversationHistorySnapshot(
        threads: const [],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
        userMessageEntriesByThreadId: {
          'thread-a': [entry],
        },
      ),
    );

    final restored = await store.read('project-a');
    final messages = restored!.userMessageEntriesByThreadId['thread-a']!;
    messages.add(
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: '第二条消息',
        createdAt: DateTime(2026),
      ),
    );

    expect(messages, hasLength(2));
  });
}
