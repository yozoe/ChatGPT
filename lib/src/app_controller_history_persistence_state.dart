import 'dart:async';

/// Owns asynchronous persistence markers shared by history and workspace saves.
///
/// The controller still builds snapshots, performs I/O, serializes operations,
/// and reports failures. This state only groups the timers, Future chains, and
/// failure marker that coordinate those side effects.
class CodexHistoryPersistenceState {
  Timer? historySaveTimer;
  Future<void> historySave = Future<void>.value();
  final Map<String, Future<void>> historySavesByWorkspace =
      <String, Future<void>>{};
  Future<void> workspaceRootsSave = Future<void>.value();
  final Map<String, Future<void>> inactiveWorkspaceCompletionQueues =
      <String, Future<void>>{};
  bool historySaveFailed = false;

  void cancelHistorySaveTimer() {
    historySaveTimer?.cancel();
    historySaveTimer = null;
  }

  void clear() {
    cancelHistorySaveTimer();
    historySave = Future<void>.value();
    historySavesByWorkspace.clear();
    workspaceRootsSave = Future<void>.value();
    inactiveWorkspaceCompletionQueues.clear();
    historySaveFailed = false;
  }
}
