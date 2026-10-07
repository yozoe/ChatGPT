import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_configuration_refresh_state.dart';

void main() {
  test('keeps configuration, model, and collaboration markers independent', () {
    final state = CodexConfigurationRefreshState();

    expect(state.nextConfigurationRequest(), 1);
    expect(state.nextModelCatalogRequest(), 1);
    expect(state.nextCollaborationModesRequest(), 1);
    expect(state.configurationRequest, 1);
    expect(state.modelCatalogRequest, 1);
    expect(state.collaborationModesRequest, 1);
  });

  test(
    'invalidates only configuration reads when runtime values are cleared',
    () {
      final state = CodexConfigurationRefreshState()
        ..configurationRequest = 3
        ..modelCatalogRequest = 5
        ..collaborationModesRequest = 7;

      state.invalidateConfiguration();

      expect(state.configurationRequest, 4);
      expect(state.modelCatalogRequest, 5);
      expect(state.collaborationModesRequest, 7);
    },
  );
}
