import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_history_persistence_state.dart';

void main() {
  test('cancels the coalesced history timer without touching save queues', () {
    final state = CodexHistoryPersistenceState();
    final timer = Timer(const Duration(hours: 1), () {});
    state.historySaveTimer = timer;
    state.historySaveFailed = true;
    state.historySavesByWorkspace['/project'] = Future<void>.value();

    state.cancelHistorySaveTimer();

    expect(timer.isActive, isFalse);
    expect(state.historySaveTimer, isNull);
    expect(state.historySaveFailed, isTrue);
    expect(state.historySavesByWorkspace, contains('/project'));
  });

  test('clear resets timers, queues, and failure state', () {
    final state = CodexHistoryPersistenceState()
      ..historySaveFailed = true
      ..historySavesByWorkspace['/project'] = Future<void>.value()
      ..inactiveWorkspaceCompletionQueues['/other'] = Future<void>.value();
    state.historySaveTimer = Timer(const Duration(hours: 1), () {});

    state.clear();

    expect(state.historySaveTimer, isNull);
    expect(state.historySavesByWorkspace, isEmpty);
    expect(state.inactiveWorkspaceCompletionQueues, isEmpty);
    expect(state.historySaveFailed, isFalse);
  });
}
