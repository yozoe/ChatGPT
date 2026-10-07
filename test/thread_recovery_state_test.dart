import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_archived_thread_restore.dart';
import 'package:chatgpt/src/app_controller_support.dart';
import 'package:chatgpt/src/app_controller_thread_recovery_state.dart';
import 'package:chatgpt/src/app_controller_thread_writer_conflict.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';

void main() {
  test('clears writer conflict payload and feedback together', () {
    final state = CodexThreadRecoveryState()
      ..threadWriterConflict = ThreadWriterConflict(
        workspace: '/workspace',
        threads: [
          CodexThread(
            id: 'thread-1',
            preview: 'preview',
            createdAt: 1,
            updatedAt: 1,
            status: 'idle',
          ),
        ],
        operation: ThreadWriterConflictOperation.resume,
      )
      ..threadWriterConflictFeedback = 'retry later';

    state.clearThreadWriterConflict();

    expect(state.threadWriterConflict, isNull);
    expect(state.threadWriterConflictFeedback, isNull);
  });

  test('clears archive restore independently from writer recovery', () {
    final state = CodexThreadRecoveryState()
      ..archivedThreadRestore = ArchivedThreadRestore(
        workspace: '/workspace',
        thread: CodexThread(
          id: 'thread-2',
          preview: 'archived',
          createdAt: 2,
          updatedAt: 2,
          status: 'archived',
        ),
      )
      ..threadWriterConflictFeedback = 'keep this';

    state.clearArchivedThreadRestore();

    expect(state.archivedThreadRestore, isNull);
    expect(state.threadWriterConflictFeedback, 'keep this');
  });
}
