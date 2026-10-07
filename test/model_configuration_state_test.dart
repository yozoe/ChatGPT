import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/app_controller_model_configuration_state.dart';
import 'package:chatgpt/src/app_controller_reasoning_effort.dart';

void main() {
  test('runtime configuration clearing preserves user selections', () {
    final state = CodexModelConfigurationState()
      ..configuredModelId = 'gpt-test'
      ..configuredProviderId = 'openai'
      ..selectedModelId = 'gpt-test'
      ..reasoningEffortsByModel = {
        'gpt-test': {ReasoningEffort.high},
      }
      ..codexConfigurationRead = true
      ..agentDefaultSettingsWriteSupported = true;

    state.clearRuntimeResolvedConfiguration();

    expect(state.configuredModelId, isNull);
    expect(state.configuredProviderId, isNull);
    expect(state.reasoningEffortsByModel, isEmpty);
    expect(state.codexConfigurationRead, isFalse);
    expect(state.agentDefaultSettingsWriteSupported, isFalse);
    expect(state.selectedModelId, 'gpt-test');
  });

  test('serialized write chains start independently', () {
    final state = CodexModelConfigurationState();

    expect(state.reasoningEffortSave, isA<Future<void>>());
    expect(state.modelSelectionSave, isA<Future<void>>());
    expect(state.approvalModeSave, isA<Future<void>>());
    expect(state.agentDefaultSettingsWrite, isA<Future<void>>());
  });
}
