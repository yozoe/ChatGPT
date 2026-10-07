import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_network_retry_event.dart';

void main() {
  test('accepts a retry only for the tracked turn', () {
    final event = CodexNetworkRetryEvent.fromParams(
      {'willRetry': true, 'threadId': 'thread-1', 'turnId': 'turn-1'},
      isActiveTurn: true,
      expectedTurnId: 'turn-1',
    );

    expect(event, isNotNull);
    expect(event!.threadId, 'thread-1');
    expect(event.turnId, 'turn-1');
    expect(event.isActiveTurn, isTrue);
  });

  test('preserves background ownership without promoting it to active', () {
    final event = CodexNetworkRetryEvent.fromParams(
      {
        'willRetry': true,
        'threadId': 'background-thread',
        'turnId': 'background-turn',
      },
      isActiveTurn: false,
      expectedTurnId: 'background-turn',
    );

    expect(event, isNotNull);
    expect(event!.threadId, 'background-thread');
    expect(event.isActiveTurn, isFalse);
  });

  test('rejects stale, failed, and incomplete retry notifications', () {
    final cases = <Map<String, dynamic>>[
      {'willRetry': false, 'threadId': 'thread-1', 'turnId': 'turn-1'},
      {'willRetry': true, 'threadId': 'thread-1', 'turnId': 'old-turn'},
      {'willRetry': true, 'threadId': 'thread-1'},
      {'willRetry': true, 'turnId': 'turn-1'},
    ];

    for (final params in cases) {
      expect(
        CodexNetworkRetryEvent.fromParams(
          params,
          isActiveTurn: false,
          expectedTurnId: 'turn-1',
        ),
        isNull,
      );
    }
  });
}
