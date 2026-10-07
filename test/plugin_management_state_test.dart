import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_plugin_management_state.dart';

void main() {
  test('keeps plugin, Skill, marketplace, and MCP state independent', () {
    final state = CodexPluginManagementState();

    state.pluginsLoading = true;
    state.skillsError = 'skills failed';
    state.marketplacesLoading = true;
    state.runtimeMcpServerStatusesError = 'mcp failed';

    expect(state.pluginsLoading, isTrue);
    expect(state.skillsError, 'skills failed');
    expect(state.marketplacesLoading, isTrue);
    expect(state.runtimeMcpServerStatusesError, 'mcp failed');
  });

  test('clears workspace MCP snapshots without touching other catalogs', () {
    final state = CodexPluginManagementState()
      ..mcpServersLoading = true
      ..mcpServersError = 'old mcp error'
      ..runtimeMcpServerStatusesLoading = true
      ..runtimeMcpServerStatusesError = 'old runtime error'
      ..runtimeMcpServerStatusesThreadId = 'thread-1'
      ..skillsLoading = true
      ..skillsError = 'keep skills error'
      ..pluginsError = 'keep plugin error';

    state.clearWorkspaceMcp();

    expect(state.mcpServers, isEmpty);
    expect(state.mcpServersLoading, isFalse);
    expect(state.mcpServersError, isNull);
    expect(state.runtimeMcpServerStatuses, isEmpty);
    expect(state.runtimeMcpServerStatusesLoading, isFalse);
    expect(state.runtimeMcpServerStatusesError, isNull);
    expect(state.runtimeMcpServerStatusesThreadId, isNull);
    expect(state.skillsLoading, isTrue);
    expect(state.skillsError, 'keep skills error');
    expect(state.pluginsError, 'keep plugin error');
  });
}
