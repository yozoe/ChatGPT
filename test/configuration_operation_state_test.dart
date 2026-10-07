import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_configuration_operation_state.dart';

void main() {
  test('keeps config probing and queued writes on independent generations', () {
    final state = CodexConfigurationOperationState();

    expect(state.isConfigWriterProbeCurrent(1), isFalse);
    state.markConfigWriterProbe(1);
    expect(state.isConfigWriterProbeCurrent(1), isTrue);
    expect(state.nextAgentDefaultSettingsWriteGeneration(), 1);
    expect(state.nextAgentDefaultSettingsWriteGeneration(), 2);
    expect(state.isAgentDefaultSettingsWriteCurrent(1), isFalse);
    expect(state.isAgentDefaultSettingsWriteCurrent(2), isTrue);
  });

  test('invalidating a probe does not invalidate a queued write', () {
    final state = CodexConfigurationOperationState()..markConfigWriterProbe(7);
    final generation = state.nextAgentDefaultSettingsWriteGeneration();

    state.invalidateConfigWriterProbe();

    expect(state.isConfigWriterProbeCurrent(7), isFalse);
    expect(state.isAgentDefaultSettingsWriteCurrent(generation), isTrue);
  });
}
