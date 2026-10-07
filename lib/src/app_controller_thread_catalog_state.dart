import 'package:chatgpt/src/domain/codex_thread.dart';

/// Owns active/archived thread catalog snapshots and local terminal metadata.
///
/// Refresh requests, merging rules, persistence, and notifications remain in
/// the controller. This state only keeps the sidebar-facing catalog values.
class CodexThreadCatalogState {
  List<CodexThread> threads = const [];
  List<CodexThread> archivedThreads = const [];
  bool threadsLoading = false;
  String? threadsError;
  bool archivedThreadsLoading = false;
  String? archivedThreadsError;
  final Map<String, String> localThreadStatuses = {};

  void clear() {
    threads = const [];
    archivedThreads = const [];
    threadsLoading = false;
    threadsError = null;
    archivedThreadsLoading = false;
    archivedThreadsError = null;
    localThreadStatuses.clear();
  }
}
