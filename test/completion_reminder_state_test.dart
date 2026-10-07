import 'package:chatgpt/src/app_controller_completion_reminder_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears session-only reminder and completion replay state', () {
    final state = CodexCompletionReminderState()
      ..acknowledgedThreadIds.add('thread-1')
      ..unacknowledgedThreadIds.add('thread-2')
      ..notifiedCompletionKeys.add('thread-2:turn-1')
      ..handledTurnCompletionKeys.add('thread-2:turn-1');

    state.clearSessionReminders();

    expect(state.acknowledgedThreadIds, {'thread-1'});
    expect(state.unacknowledgedThreadIds, isEmpty);
    expect(state.notifiedCompletionKeys, isEmpty);
    expect(state.handledTurnCompletionKeys, isEmpty);
  });

  test('clear removes persisted acknowledgements as well', () {
    final state = CodexCompletionReminderState()
      ..acknowledgedThreadIds.add('thread-1')
      ..unacknowledgedThreadIds.add('thread-1');

    state.clear();

    expect(state.acknowledgedThreadIds, isEmpty);
    expect(state.unacknowledgedThreadIds, isEmpty);
  });
}
