import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_plugin_refresh_state.dart';

void main() {
  test('keeps plugin, marketplace, skill, and MCP markers independent', () {
    final state = CodexPluginRefreshState();

    expect(state.nextPluginsRequest(), 1);
    expect(state.nextMarketplacesRequest(), 1);
    expect(state.nextSkillsRequest(), 1);
    expect(state.nextMcpServersRequest(), 1);
    expect(state.nextRuntimeMcpStatusesRequest(), 1);
    expect(state.pluginsRequest, 1);
    expect(state.marketplacesRequest, 1);
    expect(state.skillsRequest, 1);
    expect(state.mcpServersRequest, 1);
    expect(state.runtimeMcpStatusesRequest, 1);
  });

  test('invalidates plugin catalog and workspace MCP groups separately', () {
    final state = CodexPluginRefreshState()
      ..pluginsRequest = 4
      ..marketplacesRequest = 7
      ..mcpServersRequest = 2
      ..runtimeMcpStatusesRequest = 5
      ..skillsRequest = 3;

    state.invalidatePluginCatalog();

    expect(state.pluginsRequest, 5);
    expect(state.marketplacesRequest, 8);
    expect(state.mcpServersRequest, 2);
    expect(state.runtimeMcpStatusesRequest, 5);
    expect(state.skillsRequest, 3);

    state.invalidateMcpWorkspace();

    expect(state.pluginsRequest, 5);
    expect(state.marketplacesRequest, 8);
    expect(state.mcpServersRequest, 3);
    expect(state.runtimeMcpStatusesRequest, 6);
    expect(state.skillsRequest, 3);
  });
}
