import 'dart:io';

import 'package:chatgpt/src/domain/codex_thread.dart';
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
