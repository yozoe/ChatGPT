import 'package:chatgpt/src/app_controller_plugin_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_fakes/managed_runtime_fake_server.dart';
import 'widget_fakes/memory_codex_plugin_store.dart';

void main() {
  test('reads plugin, marketplace, MCP, and parsed Skill catalogs', () async {
    final store = MemoryCodexPluginStore();
    final server = ManagedRuntimeFakeServer()
      ..skillListResponse = [
        {
          'name': 'review',
          'path': '/workspace/.codex/skills/review',
          'description': 'Review code',
          'scope': 'project',
          'interface': {'displayName': 'Code Review'},
        },
        {'name': 'invalid'},
      ];
    final catalog = CodexPluginCatalog(pluginStore: store, server: server);

    final plugins = await catalog.listPlugins();
    final marketplaces = await catalog.listMarketplaces();
    final mcpServers = await catalog.listMcpServers(
      workingDirectory: '/workspace',
    );
    final skills = await catalog.listSkills(
      workingDirectory: '/workspace',
      forceReload: true,
    );

    expect(plugins, isEmpty);
    expect(marketplaces, isEmpty);
    expect(mcpServers, isEmpty);
    expect(skills.single.label, 'Code Review');
    expect(server.skillListDirectories, ['/workspace']);
  });
}
