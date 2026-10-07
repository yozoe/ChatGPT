import 'package:chatgpt/src/app_controller_goal_plan_state.dart';
import 'package:chatgpt/src/domain/codex_thread_goal.dart';
import 'package:chatgpt/src/domain/pending_plan_implementation_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears continuation flags without dropping goal snapshots', () {
    final state = CodexGoalPlanState()
      ..threadGoalsById['thread-1'] = const CodexThreadGoal(
        threadId: 'thread-1',
        objective: 'Ship the change',
        status: 'active',
      )
      ..goalContinuationPendingThreadIds.add('thread-1')
      ..goalContinuationAwaitingAcceptanceThreadIds.add('thread-1')
      ..automaticGoalTurnThreadIds.add('thread-1')
      ..goalTurnsWithToolCalls.add('thread-1')
      ..goalContinuationSuppressedThreadIds.add('thread-1')
      ..goalPauseRequestedThreadIds.add('thread-1')
      ..goalContinuationErrorsByThread['thread-1'] = 'waiting';

    state.clearGoalContinuationState();

    expect(state.threadGoalsById, hasLength(1));
    expect(state.goalContinuationPendingThreadIds, isEmpty);
    expect(state.goalContinuationAwaitingAcceptanceThreadIds, isEmpty);
    expect(state.automaticGoalTurnThreadIds, isEmpty);
    expect(state.goalTurnsWithToolCalls, isEmpty);
    expect(state.goalContinuationSuppressedThreadIds, isEmpty);
    expect(state.goalPauseRequestedThreadIds, isEmpty);
    expect(state.goalContinuationErrorsByThread, isEmpty);
  });

  test('clears plan hand-offs and mode selections together', () {
    final state = CodexGoalPlanState()
      ..newThreadPlanMode = true
      ..planModeByThreadId['thread-1'] = true
      ..planImplementationCandidates['thread-1:turn-1'] =
          const PendingPlanImplementationRequest(
            threadId: 'thread-1',
            turnId: 'turn-1',
            planContent: 'Implement the change',
          )
      ..pendingPlanImplementations['thread-1'] =
          const PendingPlanImplementationRequest(
            threadId: 'thread-1',
            turnId: 'turn-1',
            planContent: 'Implement the change',
          )
      ..successfulPlanTurnKeys.add('thread-1:turn-1')
      ..rejectedPlanTurnKeys.add('thread-1:turn-2')
      ..handledPlanImplementationKeys.add('thread-1:turn-0');

    state.clear();

    expect(state.newThreadPlanMode, isFalse);
    expect(state.planModeByThreadId, isEmpty);
    expect(state.planImplementationCandidates, isEmpty);
    expect(state.pendingPlanImplementations, isEmpty);
    expect(state.successfulPlanTurnKeys, isEmpty);
    expect(state.rejectedPlanTurnKeys, isEmpty);
    expect(state.handledPlanImplementationKeys, isEmpty);
  });
}
