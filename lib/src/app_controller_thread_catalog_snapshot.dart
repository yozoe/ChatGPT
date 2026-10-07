import 'package:chatgpt/src/domain/codex_thread.dart';

/// Immutable Riverpod-facing snapshot of the sidebar thread catalog.
class CodexThreadCatalogSnapshot {
  const CodexThreadCatalogSnapshot({
    required this.threads,
    required this.archivedThreads,
    required this.threadsLoading,
    required this.threadsError,
    required this.archivedThreadsLoading,
    required this.archivedThreadsError,
    required this.localThreadStatuses,
  });

  factory CodexThreadCatalogSnapshot.fromValues({
    required Iterable<CodexThread> threads,
    required Iterable<CodexThread> archivedThreads,
    required bool threadsLoading,
    required String? threadsError,
    required bool archivedThreadsLoading,
    required String? archivedThreadsError,
    required Map<String, String> localThreadStatuses,
  }) {
    return CodexThreadCatalogSnapshot(
      threads: List<CodexThread>.unmodifiable(threads),
      archivedThreads: List<CodexThread>.unmodifiable(archivedThreads),
      threadsLoading: threadsLoading,
      threadsError: threadsError,
      archivedThreadsLoading: archivedThreadsLoading,
      archivedThreadsError: archivedThreadsError,
      localThreadStatuses: Map<String, String>.unmodifiable(
        localThreadStatuses,
      ),
    );
  }

  final List<CodexThread> threads;
  final List<CodexThread> archivedThreads;
  final bool threadsLoading;
  final String? threadsError;
  final bool archivedThreadsLoading;
  final String? archivedThreadsError;
  final Map<String, String> localThreadStatuses;
}
