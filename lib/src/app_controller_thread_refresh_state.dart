/// Owns monotonically increasing markers for active and archived thread reads.
///
/// The controller still decides when a response is accepted and owns the
/// workspace/server checks. This state only provides independent counters so
/// stale list responses can be invalidated without sharing unrelated epochs.
class CodexThreadRefreshState {
  int refreshEpoch = 0;
  int activeRequest = 0;
  int archivedRequest = 0;

  int nextActiveRequest() => ++activeRequest;

  int nextArchivedRequest() => ++archivedRequest;

  void invalidateAll() {
    refreshEpoch++;
    invalidateActive();
    archivedRequest++;
  }

  void invalidateActive() {
    activeRequest++;
  }
}
