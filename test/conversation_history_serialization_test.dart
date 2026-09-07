import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:chatgpt/src/services/local_session_thread_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('caches local session metadata during the refresh interval', () async {
    final directory = await Directory.systemTemp.createTemp('codex-sessions-');
    addTearDown(() => directory.delete(recursive: true));
    final sessionFile = File('${directory.path}/rollout.jsonl');
    await sessionFile.writeAsString(
      '${jsonEncode({
        'type': 'session_meta',
        'payload': {'session_id': 'cached-thread', 'timestamp': '2026-08-20T00:00:00.000Z', 'cwd': '/workspace'},
      })}\n',
    );
    final store = LocalSessionThreadStore(directory: directory);

    expect((await store.listThreads('/workspace')).single.id, 'cached-thread');
    await sessionFile.delete();

    expect((await store.listThreads('/workspace')).single.id, 'cached-thread');
  });

  test('serializes consecutive local history writes', () async {
    final store = BlockingConversationHistoryStore();
    final controller =
        CodexController(
            server: CodexAppServer(),
            conversationHistoryStore: store,
          )
          ..workspacePath = '/workspace'
          ..threads = [thread(id: 'first-thread')];

    final firstSave = controller.saveConversationHistoryForTesting();
    await store.firstSaveStarted.future;
    controller.threads = [thread(id: 'second-thread')];
    final secondSave = controller.saveConversationHistoryForTesting();

    expect(store.saveCalls, 1);
    store.allowFirstSave.complete();
    await Future.wait([firstSave, secondSave]);

    expect(store.snapshots['/workspace']!.threads.single.id, 'second-thread');
    controller.dispose();
  });

  test('ignores malformed collection fields in cached history snapshots', () {
    final snapshot = ConversationHistorySnapshot.fromJson({
      'threads': 'invalid',
      'archivedThreads': 42,
      'entries': null,
      'fileChanges': {'invalid': true},
      'pinnedThreadIds': [null, '', 'kept-thread'],
      'turnDiff': 123,
    });

    expect(snapshot.threads, isEmpty);
    expect(snapshot.archivedThreads, isEmpty);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.fileChanges, isEmpty);
    expect(snapshot.pinnedThreadIds, {'kept-thread'});
    expect(snapshot.turnDiff, '123');
  });

  test('round-trips first-class conversation activity metadata', () {
    final entry = TimelineEntry(
      kind: TimelineKind.activity,
      title: 'Independent review',
      detail: '已完成',
      createdAt: DateTime(2026, 8, 25, 10, 30),
      sourceItemId: 'review-thread',
      activityKind: 'collaboration',
      activityStatus: 'completed',
      linkedThreadId: 'review-thread',
      activityPrompt: 'Review the changed files.',
    );

    final restored = TimelineEntry.fromJson(entry.toJson());

    expect(restored.id, entry.id);
    expect(restored.kind, TimelineKind.activity);
    expect(restored.title, 'Independent review');
    expect(restored.detail, '已完成');
    expect(restored.sourceItemId, 'review-thread');
    expect(restored.activityKind, 'collaboration');
    expect(restored.activityStatus, 'completed');
    expect(restored.linkedThreadId, 'review-thread');
    expect(restored.activityPrompt, 'Review the changed files.');
  });

  test('assigns a stable ID when restoring legacy timeline entries', () {
    final restored = TimelineEntry.fromJson({
      'kind': 'agent',
      'title': 'Codex',
      'detail': '旧缓存回答',
      'createdAt': DateTime(2026).toIso8601String(),
    });

    expect(restored.id, isNotEmpty);
    expect(restored.copyWith(detail: '更新后的回答').id, restored.id);
  });

  test('rejects unsupported portable history schemas', () {
    expect(
      () => PortableConversationHistory.fromJson({
        'format': 'codex-desk-history',
        'version': 999,
        'snapshot': <String, Object?>{},
      }),
      throwsFormatException,
    );
  });
}

CodexThread thread({required String id}) =>
    CodexThread(id: id, preview: 'preview-$id', createdAt: 1, updatedAt: 2);
