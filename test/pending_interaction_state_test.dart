import 'dart:async';

import 'package:chatgpt/src/app_controller_pending_interaction_state.dart';
import 'package:chatgpt/src/domain/pending_approval.dart';
import 'package:chatgpt/src/domain/pending_elicitation.dart';
import 'package:chatgpt/src/domain/pending_user_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clear cancels auto-resolution timers and request queues', () {
    final timer = Timer(const Duration(hours: 1), () {});
    final state = CodexPendingInteractionState()
      ..userInputAutoResolutionTimers['request-1'] = timer
      ..userInputAutoResolutionStates['request-1'] = 'scheduled'
      ..userInputAutoResolutionDeadlines['request-1'] = DateTime(2030)
      ..autoResolvingUserInputByThread['thread-1'] = 'request-1'
      ..pendingRequestOrder.add((requestId: 'request-1', kind: 'userInput'))
      ..approvalResponding = true
      ..elicitationResponding = true
      ..userInputResponding = true;

    state.clear();

    expect(timer.isActive, isFalse);
    expect(state.userInputAutoResolutionTimers, isEmpty);
    expect(state.userInputAutoResolutionStates, isEmpty);
    expect(state.userInputAutoResolutionDeadlines, isEmpty);
    expect(state.autoResolvingUserInputByThread, isEmpty);
    expect(state.pendingRequestOrder, isEmpty);
    expect(state.approvalResponding, isFalse);
    expect(state.elicitationResponding, isFalse);
    expect(state.userInputResponding, isFalse);
  });

  test('keeps request collections independently addressable', () {
    final state = CodexPendingInteractionState();
    state.pendingApprovals['approval'] = const PendingApproval(
      requestId: 'approval',
      method: 'item/commandExecution/requestApproval',
      params: {},
      kind: ApprovalKind.command,
    );
    state.pendingElicitations['elicitation'] = const PendingElicitation(
      requestId: 'elicitation',
      params: {},
      mode: ElicitationMode.url,
      message: 'Open link',
      serverName: 'MCP',
      url: 'https://example.com',
    );
    state.pendingUserInputs['input'] = const PendingUserInputRequest(
      requestId: 'input',
      params: {},
      threadId: 'thread-1',
      turnId: 'turn-1',
      itemId: 'item-1',
      questions: [],
      isBlocking: true,
    );

    expect(state.pendingApprovals, contains('approval'));
    expect(state.pendingElicitations, contains('elicitation'));
    expect(state.pendingUserInputs, contains('input'));
  });

  test(
    'clearForRuntimeDisconnect drops protocol requests but keeps surface state',
    () {
      final state = CodexPendingInteractionState()
        ..userInputSurfaceForegrounded = true
        ..presentedUserInputThreadId = 'thread-1'
        ..approvalResponding = true
        ..elicitationResponding = true
        ..userInputResponding = true;

      state.clearForRuntimeDisconnect();

      expect(state.pendingApprovals, isEmpty);
      expect(state.pendingElicitations, isEmpty);
      expect(state.pendingUserInputs, isEmpty);
      expect(state.pendingRequestOrder, isEmpty);
      expect(state.userInputSurfaceForegrounded, isTrue);
      expect(state.presentedUserInputThreadId, 'thread-1');
      expect(state.approvalResponding, isFalse);
      expect(state.elicitationResponding, isFalse);
      expect(state.userInputResponding, isFalse);
    },
  );
}
