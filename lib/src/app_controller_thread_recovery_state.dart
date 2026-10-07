import 'app_controller_archived_thread_restore.dart';
import 'app_controller_thread_writer_conflict.dart';

/// Owns ephemeral recovery prompts for thread writer and archive conflicts.
///
/// The controller still decides when to retry, unarchive, notify, or restore
/// a timeline. This state only keeps the prompt payload and its short-lived
/// progress/error markers together.
class CodexThreadRecoveryState {
  ThreadWriterConflict? threadWriterConflict;
  bool retryingThreadWriterConflict = false;
  String? threadWriterConflictFeedback;
  ArchivedThreadRestore? archivedThreadRestore;
  bool restoringArchivedThread = false;

  void clearThreadWriterConflict() {
    threadWriterConflict = null;
    threadWriterConflictFeedback = null;
  }

  void clearArchivedThreadRestore() {
    archivedThreadRestore = null;
  }
}
