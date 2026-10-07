import 'package:chatgpt/src/domain/codex_file_change.dart';

/// Owns the mutable file-change collections shared by the active thread and
/// its cached historical views.
///
/// The controller still decides when a turn starts, how a Diff is reconciled,
/// and when persistence is written. This type only groups the collections so
/// file/Diff state does not remain spread across the controller's other
/// domains.
class CodexFileChangeState {
  final Map<String, CodexFileChange> fileChangesByPath =
      <String, CodexFileChange>{};
  final Map<String, CodexFileChange> turnFileChangesByPath =
      <String, CodexFileChange>{};
  final Set<String> turnDiffDerivedFileChangePaths = <String>{};
  final Set<String> turnExplicitFileChangePaths = <String>{};
  final Map<String, List<CodexFileChange>> persistedFileChangesByThreadId =
      <String, List<CodexFileChange>>{};
  final Map<String, List<CodexFileChange>> persistedTurnFileChangesByThreadId =
      <String, List<CodexFileChange>>{};
  final Map<String, List<CodexFileChange>>
  persistedFileChangesBeforeTurnByThreadId = <String, List<CodexFileChange>>{};
  final Map<String, String?> persistedTurnDiffByThreadId = <String, String?>{};

  void clearCurrentTurn() {
    turnFileChangesByPath.clear();
    turnDiffDerivedFileChangePaths.clear();
    turnExplicitFileChangePaths.clear();
  }

  void removeThread(String threadId) {
    persistedFileChangesByThreadId.remove(threadId);
    persistedTurnFileChangesByThreadId.remove(threadId);
    persistedFileChangesBeforeTurnByThreadId.remove(threadId);
    persistedTurnDiffByThreadId.remove(threadId);
  }

  void clear() {
    fileChangesByPath.clear();
    clearCurrentTurn();
    persistedFileChangesByThreadId.clear();
    persistedTurnFileChangesByThreadId.clear();
    persistedFileChangesBeforeTurnByThreadId.clear();
    persistedTurnDiffByThreadId.clear();
  }
}
