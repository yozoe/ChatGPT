import 'app_controller_support.dart';

/// Owns mutable lifecycle markers for the local runtime connection.
///
/// The controller still performs the actual App Server orchestration and
/// status transitions. This state only groups the epoch and small counters
/// used to reject stale asynchronous work and identify retry timeline items.
class CodexRuntimeConnectionState {
  bool isStarting = false;
  int connectionEpoch = 0;
  int networkRetryEventSequence = 0;

  /// Advances the connection epoch for a new startup attempt.
  int beginConnection() => ++connectionEpoch;

  /// Invalidates all asynchronous work belonging to the previous connection.
  int invalidateConnection() => ++connectionEpoch;

  bool isCurrent(int epoch, {required bool isDisposed}) =>
      !isDisposed && epoch == connectionEpoch;

  /// Returns a monotonic suffix for a network-retry timeline item.
  int nextNetworkRetrySequence() => networkRetryEventSequence++;

  /// Whether a new startup request would duplicate an active connection.
  bool blocksStart(RuntimeStatus status) =>
      isStarting ||
      status == RuntimeStatus.starting ||
      status == RuntimeStatus.ready ||
      status == RuntimeStatus.running;

  /// Whether reconnect must wait for an existing startup or running task.
  bool blocksReconnect(RuntimeStatus status, {required bool hasRunningTasks}) =>
      hasRunningTasks || status == RuntimeStatus.starting || isStarting;

  /// Whether the current connection should be stopped before replacement.
  bool requiresStop(RuntimeStatus status, {required bool serverRunning}) =>
      serverRunning || status == RuntimeStatus.ready;

  void clear() {
    isStarting = false;
    connectionEpoch = 0;
    networkRetryEventSequence = 0;
  }
}
