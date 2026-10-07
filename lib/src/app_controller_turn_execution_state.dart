import 'dart:async';

import 'package:chatgpt/src/app_controller_failed_turn_retry.dart';
import 'package:chatgpt/src/app_controller_turn_submission.dart';
import 'package:chatgpt/src/app_controller_support.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/domain/codex_thread_token_usage.dart';
import 'package:chatgpt/src/services/codex_app_server_support.dart';

/// 集中维护回合发送、失败重试、网络恢复和线程级运行元数据。
/// Owns turn submission, failed-turn retry, network recovery, and per-thread execution metadata.
///
/// 控制器仍负责请求编排、时间线写入和生命周期回调；本类型只归组异步
/// 回合流程共享的可变集合。
/// The controller still coordinates requests, timeline writes, and lifecycle
/// callbacks; this type only groups mutable collections shared by async turn flows.
class CodexTurnExecutionState {
  bool preparingTurnStart = false;
  bool turnStartAwaitingAcceptance = false;
  final Set<int> sendPromptInFlightRevisions = <int>{};
  final Map<String, String> runningTurnIdsByThread = <String, String>{};
  final Map<String, List<TimelineEntry>> pendingNetworkRetryEntriesByThread =
      <String, List<TimelineEntry>>{};
  final Map<String, TurnSubmission> runningTurnSubmissions =
      <String, TurnSubmission>{};
  final Map<String, FailedTurnRetry> failedTurnRetries =
      <String, FailedTurnRetry>{};
  final Map<String, int> automaticRetryAttempts = <String, int>{};
  final Map<String, DateTime> automaticRetryDeadlines = <String, DateTime>{};
  final Map<String, Timer> automaticRetryTimers = <String, Timer>{};
  final Set<String> automaticRetryCancelled = <String>{};
  String? retryingFailedTurnThreadId;

  final Map<String, JsonMap> threadCollaborationModesById = <String, JsonMap>{};
  final Map<String, CodexThreadTokenUsage> threadTokenUsageById =
      <String, CodexThreadTokenUsage>{};

  void cancelAutomaticRetry(String threadId) {
    automaticRetryTimers.remove(threadId)?.cancel();
    automaticRetryDeadlines.remove(threadId);
    automaticRetryCancelled.add(threadId);
  }

  /// Finalizes the per-thread execution bookkeeping for a completed turn.
  ///
  /// The controller remains responsible for timeline, worktree, notification,
  /// and timer side effects. This method only moves the exact submission into
  /// the retry map when the turn failed, and clears the in-flight identifiers.
  FailedTurnRetry? recordTurnCompletion({
    required String threadId,
    required TurnCompletionOutcome outcome,
    required String error,
    FailedTurnKind kind = FailedTurnKind.retryable,
  }) {
    runningTurnIdsByThread.remove(threadId);
    final submission = runningTurnSubmissions.remove(threadId);
    if (outcome == TurnCompletionOutcome.failed && submission != null) {
      final retry = FailedTurnRetry(
        submission: submission,
        error: error,
        kind: kind,
      );
      failedTurnRetries[threadId] = retry;
      return retry;
    }
    failedTurnRetries.remove(threadId);
    return null;
  }

  /// Marks waiting network-retry activities historical for the matching turn.
  /// Returns whether the active timeline changed and therefore needs saving.
  bool markNetworkRetryActivitiesHistorical({
    required String threadId,
    required String turnId,
    required String? activeThreadId,
    required String? activeTurnId,
    required List<TimelineEntry> activeEntries,
  }) {
    final expectedTurnId = threadId == activeThreadId
        ? activeTurnId
        : runningTurnIdsByThread[threadId];
    if (expectedTurnId != turnId) return false;
    var activeTimelineChanged = false;
    if (threadId == activeThreadId) {
      for (var index = 0; index < activeEntries.length; index++) {
        final entry = activeEntries[index];
        if (entry.activityKind != 'networkRetry' ||
            entry.activityStatus != 'waiting') {
          continue;
        }
        activeEntries[index] = entry.copyWith(activityStatus: 'historical');
        activeTimelineChanged = true;
      }
    }
    final pending = pendingNetworkRetryEntriesByThread[threadId];
    if (pending != null) {
      for (var index = 0; index < pending.length; index++) {
        final entry = pending[index];
        if (entry.activityKind == 'networkRetry' &&
            entry.activityStatus == 'waiting') {
          pending[index] = entry.copyWith(activityStatus: 'historical');
        }
      }
    }
    return activeTimelineChanged;
  }

  List<TimelineEntry>? takePendingNetworkRetryEntries(String threadId) =>
      pendingNetworkRetryEntriesByThread.remove(threadId);

  void clearAutomaticRetries() {
    for (final timer in automaticRetryTimers.values) {
      timer.cancel();
    }
    automaticRetryTimers.clear();
    automaticRetryDeadlines.clear();
    automaticRetryAttempts.clear();
    automaticRetryCancelled.clear();
  }

  /// Clears turn execution data that cannot survive an explicit runtime stop.
  ///
  /// Runtime-exit handling intentionally uses a narrower path so failed-turn
  /// recovery can still reconcile the disconnected task. Keep that semantic
  /// difference outside this helper.
  void clearForRuntimeStop() {
    runningTurnIdsByThread.clear();
    pendingNetworkRetryEntriesByThread.clear();
    runningTurnSubmissions.clear();
    failedTurnRetries.clear();
    clearAutomaticRetries();
    retryingFailedTurnThreadId = null;
  }

  void clear() {
    preparingTurnStart = false;
    turnStartAwaitingAcceptance = false;
    sendPromptInFlightRevisions.clear();
    clearForRuntimeStop();
    threadCollaborationModesById.clear();
    threadTokenUsageById.clear();
  }
}
