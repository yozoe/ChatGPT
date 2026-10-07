import 'package:chatgpt/src/app_controller_agent_message_stream_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks stream identity and clones without sharing mutable state', () {
    final state = CodexAgentMessageStreamState()
      ..entryIndexByItem['message-1'] = 2
      ..phaseByItem['message-1'] = 'commentary'
      ..completedItemIds.add('message-0')
      ..activeItemId = 'message-1';

    final clone = state.clone();
    clone.entryIndexByItem['message-2'] = 5;
    clone.phaseByItem['message-1'] = 'final_answer';
    clone.completedItemIds.add('message-2');
    clone.activeItemId = 'message-2';

    expect(state.entryIndexByItem, {'message-1': 2});
    expect(state.phaseByItem['message-1'], 'commentary');
    expect(state.completedItemIds, {'message-0'});
    expect(state.activeItemId, 'message-1');
  });

  test('shifts timeline indexes and restores a prior snapshot', () {
    final state = CodexAgentMessageStreamState()
      ..entryIndexByItem.addAll({'first': 1, 'second': 3})
      ..activeItemId = 'second';
    final snapshot = state.clone();

    state.shiftEntryIndexes(2);
    expect(state.entryIndexByItem, {'first': 1, 'second': 4});

    state
      ..entryIndexByItem.clear()
      ..activeItemId = 'other';
    state.restoreFrom(snapshot);
    expect(state.entryIndexByItem, {'first': 1, 'second': 3});
    expect(state.activeItemId, 'second');
  });

  test('clear removes all per-turn stream state', () {
    final state = CodexAgentMessageStreamState()
      ..entryIndexByItem['message'] = 1
      ..phaseByItem['message'] = 'final_answer'
      ..completedItemIds.add('message')
      ..activeItemId = 'message';

    state.clear();

    expect(state.entryIndexByItem, isEmpty);
    expect(state.phaseByItem, isEmpty);
    expect(state.completedItemIds, isEmpty);
    expect(state.activeItemId, isNull);
  });
}
