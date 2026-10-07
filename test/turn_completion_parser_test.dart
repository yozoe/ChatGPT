import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_support.dart';
import 'package:chatgpt/src/app_controller_turn_completion_parser.dart';

void main() {
  test('prefers the nested turn status over the envelope status', () {
    expect(
      CodexTurnCompletionParser.statusFromParams({
        'status': 'failed',
        'turn': {'status': 'completed'},
      }),
      'completed',
    );
    expect(
      CodexTurnCompletionParser.statusFromParams({'status': 'interrupted'}),
      'interrupted',
    );
  });

  test('normalizes compatible successful, stopped, and failed statuses', () {
    expect(
      CodexTurnCompletionParser.outcomeFromStatus('DONE'),
      TurnCompletionOutcome.succeeded,
    );
    expect(
      CodexTurnCompletionParser.outcomeFromStatus('cancelled'),
      TurnCompletionOutcome.stopped,
    );
    expect(
      CodexTurnCompletionParser.outcomeFromStatus('system_error'),
      TurnCompletionOutcome.failed,
    );
  });

  test('uses unknown for missing or unsupported status values', () {
    expect(
      CodexTurnCompletionParser.outcomeFromStatus(null),
      TurnCompletionOutcome.unknown,
    );
    expect(
      CodexTurnCompletionParser.outcomeFromStatus('future-status'),
      TurnCompletionOutcome.unknown,
    );
  });
}
