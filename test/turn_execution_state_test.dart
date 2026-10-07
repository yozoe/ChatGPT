import 'dart:async';

import 'package:chatgpt/src/app_controller_turn_execution_state.dart';
import 'package:chatgpt/src/app_controller_failed_turn_retry.dart';
import 'package:chatgpt/src/app_controller_support.dart';
import 'package:chatgpt/src/app_controller_turn_submission.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancels one automatic retry without dropping its attempt count', () {
    final timer = Timer(const Duration(hours: 1), () {});
    final state = CodexTurnExecutionState()
      ..automaticRetryTimers['thread-1'] = timer
      ..automaticRetryDeadlines['thread-1'] = DateTime(2030)
      ..automaticRetryAttempts['thread-1'] = 2;

    state.cancelAutomaticRetry('thread-1');

    expect(timer.isActive, isFalse);
    expect(state.automaticRetryTimers, isEmpty);
    expect(state.automaticRetryDeadlines, isEmpty);
    expect(state.automaticRetryAttempts['thread-1'], 2);
    expect(state.automaticRetryCancelled, {'thread-1'});
  });

  test('clear cancels timers and removes all turn execution metadata', () {
    final timer = Timer(const Duration(hours: 1), () {});
    final state = CodexTurnExecutionState()
      ..preparingTurnStart = true
      ..turnStartAwaitingAcceptance = true
      ..sendPromptInFlightRevisions.add(4)
      ..runningTurnIdsByThread['thread-1'] = 'turn-1'
      ..automaticRetryTimers['thread-1'] = timer
      ..automaticRetryAttempts['thread-1'] = 1
      ..retryingFailedTurnThreadId = 'thread-1'
      ..threadCollaborationModesById['thread-1'] = {'mode': 'plan'};

    state.clear();

    expect(timer.isActive, isFalse);
    expect(state.preparingTurnStart, isFalse);
    expect(state.turnStartAwaitingAcceptance, isFalse);
    expect(state.sendPromptInFlightRevisions, isEmpty);
    expect(state.runningTurnIdsByThread, isEmpty);
    expect(state.automaticRetryAttempts, isEmpty);
    expect(state.retryingFailedTurnThreadId, isNull);
    expect(state.threadCollaborationModesById, isEmpty);
  });

  test(
    'runtime stop clears turn recovery without changing collaboration data',
    () {
      final timer = Timer(const Duration(hours: 1), () {});
      final state = CodexTurnExecutionState()
        ..runningTurnIdsByThread['thread-1'] = 'turn-1'
        ..pendingNetworkRetryEntriesByThread['thread-1'] = const []
        ..automaticRetryTimers['thread-1'] = timer
        ..automaticRetryDeadlines['thread-1'] = DateTime(2030)
        ..automaticRetryAttempts['thread-1'] = 2
        ..retryingFailedTurnThreadId = 'thread-1'
        ..threadCollaborationModesById['thread-1'] = {'mode': 'plan'};

      state.clearForRuntimeStop();

      expect(timer.isActive, isFalse);
      expect(state.runningTurnIdsByThread, isEmpty);
      expect(state.pendingNetworkRetryEntriesByThread, isEmpty);
      expect(state.automaticRetryAttempts, isEmpty);
      expect(state.retryingFailedTurnThreadId, isNull);
      expect(state.threadCollaborationModesById, {
        'thread-1': {'mode': 'plan'},
      });
    },
  );

  test('retains the exact failed submission for a retry', () {
    final submission = TurnSubmission(
      workspace: '/workspace',
      threadId: 'thread-1',
      prompt: 'retry this',
      additionalInput: const [],
      additionalContext: null,
      goal: null,
      collaborationMode: null,
      imagePaths: const [],
    );
    final state = CodexTurnExecutionState()
      ..runningTurnIdsByThread['thread-1'] = 'turn-1'
      ..runningTurnSubmissions['thread-1'] = submission;

    final retry = state.recordTurnCompletion(
      threadId: 'thread-1',
      outcome: TurnCompletionOutcome.failed,
      error: 'temporary failure',
      kind: FailedTurnKind.capacityRateLimit,
    );

    expect(retry, isNotNull);
    expect(retry!.submission, same(submission));
    expect(retry.error, 'temporary failure');
    expect(retry.kind, FailedTurnKind.capacityRateLimit);
    expect(state.runningTurnIdsByThread, isEmpty);
    expect(state.runningTurnSubmissions, isEmpty);
    expect(state.failedTurnRetries['thread-1'], same(retry));
  });

  test('clears a stale retry when a later turn ends without failure', () {
    final state = CodexTurnExecutionState()
      ..failedTurnRetries['thread-1'] = FailedTurnRetry(
        submission: TurnSubmission(
          workspace: '/workspace',
          threadId: 'thread-1',
          prompt: 'old',
          additionalInput: const [],
          additionalContext: null,
          goal: null,
          collaborationMode: null,
          imagePaths: const [],
        ),
        error: 'old failure',
      );

    final retry = state.recordTurnCompletion(
      threadId: 'thread-1',
      outcome: TurnCompletionOutcome.succeeded,
      error: '',
    );

    expect(retry, isNull);
    expect(state.failedTurnRetries, isEmpty);
  });

  test('marks only matching network retry activities as historical', () {
    final active = TimelineEntry(
      kind: TimelineKind.activity,
      title: 'Reconnecting... waiting for network',
      detail: '',
      createdAt: DateTime(2026),
      activityKind: 'networkRetry',
      activityStatus: 'waiting',
    );
    final unrelated = TimelineEntry(
      kind: TimelineKind.activity,
      title: 'Other activity',
      detail: '',
      createdAt: DateTime(2026),
      activityKind: 'networkRetry',
      activityStatus: 'historical',
    );
    final pending = TimelineEntry(
      kind: TimelineKind.activity,
      title: 'Reconnecting... waiting for network',
      detail: '',
      createdAt: DateTime(2026),
      activityKind: 'networkRetry',
      activityStatus: 'waiting',
    );
    final state = CodexTurnExecutionState()
      ..runningTurnIdsByThread['thread-1'] = 'turn-1'
      ..pendingNetworkRetryEntriesByThread['thread-1'] = [pending];

    final activeEntries = [active, unrelated];
    final changed = state.markNetworkRetryActivitiesHistorical(
      threadId: 'thread-1',
      turnId: 'turn-1',
      activeThreadId: 'thread-1',
      activeTurnId: 'turn-1',
      activeEntries: activeEntries,
    );

    expect(changed, isTrue);
    expect(activeEntries[0].activityStatus, 'historical');
    expect(activeEntries[1].activityStatus, 'historical');
    expect(
      state
          .pendingNetworkRetryEntriesByThread['thread-1']!
          .single
          .activityStatus,
      'historical',
    );
  });

  test('takes pending network retry activities once', () {
    final entry = TimelineEntry(
      kind: TimelineKind.activity,
      title: 'Reconnecting... waiting for network',
      detail: '',
      createdAt: DateTime(2026),
      activityKind: 'networkRetry',
      activityStatus: 'waiting',
    );
    final state = CodexTurnExecutionState()
      ..pendingNetworkRetryEntriesByThread['thread-1'] = [entry];

    expect(state.takePendingNetworkRetryEntries('thread-1'), [entry]);
    expect(state.takePendingNetworkRetryEntries('thread-1'), isNull);
  });
}
