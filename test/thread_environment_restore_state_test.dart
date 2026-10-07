import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_thread_environment_restore_state.dart';

void main() {
  test('advances restore generations and rejects stale switches', () {
    final state = CodexThreadEnvironmentRestoreState();

    final first = state.nextGeneration();
    final second = state.nextGeneration();

    expect(first, 1);
    expect(second, 2);
    expect(state.isCurrent(first), isFalse);
    expect(state.isCurrent(second), isTrue);
  });

  test('invalidating a restore generation does not affect a new one', () {
    final state = CodexThreadEnvironmentRestoreState();
    final generation = state.nextGeneration();

    state.invalidate();

    expect(state.isCurrent(generation), isFalse);
    final next = state.nextGeneration();
    expect(next, generation + 2);
    expect(state.isCurrent(next), isTrue);
  });
}
