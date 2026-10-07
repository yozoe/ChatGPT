/// Owns thread-operation guards.
///
/// The controller still performs the App Server requests, list reconciliation,
/// writer-conflict handling, and user-facing notifications. This state only
/// groups the mutable markers used to prevent duplicate operations.
class CodexThreadOperationState {
  final Set<String> unarchivingThreadIds = <String>{};
  final Set<String> archivingThreadIds = <String>{};
  final Set<String> deletingThreadIds = <String>{};
  final Set<String> forkingThreadIds = <String>{};
}
