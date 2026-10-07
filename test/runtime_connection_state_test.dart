import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_runtime_connection_state.dart';
import 'package:chatgpt/src/app_controller_support.dart';

void main() {
  test('advances connection epochs and rejects stale work', () {
    final state = CodexRuntimeConnectionState();

    final first = state.beginConnection();
    expect(first, 1);
    expect(state.isCurrent(first, isDisposed: false), isTrue);

    final second = state.invalidateConnection();
    expect(second, 2);
    expect(state.isCurrent(first, isDisposed: false), isFalse);
    expect(state.isCurrent(second, isDisposed: false), isTrue);
    expect(state.isCurrent(second, isDisposed: true), isFalse);
  });

  test('keeps startup and retry markers independent', () {
    final state = CodexRuntimeConnectionState()..isStarting = true;

    expect(state.isStarting, isTrue);
    expect(state.nextNetworkRetrySequence(), 0);
    expect(state.nextNetworkRetrySequence(), 1);

    state.clear();

    expect(state.isStarting, isFalse);
    expect(state.connectionEpoch, 0);
    expect(state.nextNetworkRetrySequence(), 0);
  });

  test('centralizes startup, reconnect, and replacement guards', () {
    final state = CodexRuntimeConnectionState();

    expect(state.blocksStart(RuntimeStatus.stopped), isFalse);
    expect(state.blocksStart(RuntimeStatus.ready), isTrue);
    expect(
      state.blocksReconnect(RuntimeStatus.ready, hasRunningTasks: false),
      isFalse,
    );
    expect(
      state.blocksReconnect(RuntimeStatus.ready, hasRunningTasks: true),
      isTrue,
    );
    expect(
      state.requiresStop(RuntimeStatus.ready, serverRunning: false),
      isTrue,
    );
    expect(
      state.requiresStop(RuntimeStatus.stopped, serverRunning: true),
      isTrue,
    );
  });
}
