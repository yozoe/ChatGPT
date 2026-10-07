import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_runtime_probe_state.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';

void main() {
  test('tracks a successful probe without a stale error', () {
    final state = CodexRuntimeProbeState()
      ..error = 'old failure'
      ..begin();

    state.apply(
      const CodexRuntimeProbe(isAvailable: true, executablePath: '/codex'),
    );

    expect(state.probe?.isAvailable, isTrue);
    expect(state.error, isNull);
    expect(state.checking, isFalse);
  });

  test('keeps probe errors and clears the loading marker', () {
    final state = CodexRuntimeProbeState()..begin();

    state.apply(
      const CodexRuntimeProbe(isAvailable: false, error: 'CLI missing'),
    );

    expect(state.error, 'CLI missing');
    expect(state.checking, isFalse);
  });

  test('clear removes the last probe and operation state', () {
    final state = CodexRuntimeProbeState()
      ..probe = const CodexRuntimeProbe(isAvailable: true)
      ..error = 'stale'
      ..checking = true;

    state.clear();

    expect(state.probe, isNull);
    expect(state.error, isNull);
    expect(state.checking, isFalse);
  });

  test('finish closes a probe without changing its result', () {
    final state = CodexRuntimeProbeState()
      ..probe = const CodexRuntimeProbe(isAvailable: true)
      ..error = null
      ..checking = true;

    state.finish();

    expect(state.checking, isFalse);
    expect(state.probe?.isAvailable, isTrue);
    expect(state.error, isNull);
  });
}
