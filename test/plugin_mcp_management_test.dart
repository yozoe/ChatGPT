import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugin_glyph.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_plugin_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryConversationHistoryStore historyStore;
  late FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    historyStore = MemoryConversationHistoryStore();
    runtimeConfigurationStore = FakeRuntimeConfigurationStore();
    CodexController.testingConversationHistoryStore = historyStore;
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  test('lists, installs, and toggles local Codex plugins', () async {
    final pluginStore = MemoryCodexPluginStore()
      ..plugins.addAll([
        const CodexPlugin(
          id: 'installed@local',
          name: 'installed',
          marketplaceName: 'local',
          installed: true,
          enabled: true,
        ),
        const CodexPlugin(
          id: 'available@local',
          name: 'available',
          marketplaceName: 'local',
          installed: false,
          enabled: false,
        ),
      ]);
    final controller = CodexController(pluginStore: pluginStore);

    await controller.refreshPlugins();
    await controller.setPluginEnabled(controller.plugins.first, false);
    await controller.installPlugin(controller.plugins.last);
    await controller.addLocalPluginMarketplace('/plugins');

    expect(pluginStore.enabledChanges, {'installed@local': false});
    expect(pluginStore.installedPluginIds, ['available@local']);
    expect(pluginStore.addedMarketplaces, ['/plugins']);
    expect(
      controller.plugins
          .singleWhere((plugin) => plugin.id == 'available@local')
          .installed,
      true,
    );
    controller.dispose();
  });

  testWidgets('renders an SVG plugin logo with the SVG renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PluginGlyph(
            name: 'Visualize',
            active: true,
            logoPath: '/plugins/visualize/assets/visualize.svg',
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsAtLeastNWidgets(1));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('uses the Codex plugin mark when no plugin logo is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PluginGlyph(name: 'Plugin', active: false)),
      ),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(Icons.extension_outlined), findsNothing);
  });

  testWidgets('does not repeat installed plugins in the catalog', (
    tester,
  ) async {
    final pluginStore = MemoryCodexPluginStore()
      ..plugins.add(
        const CodexPlugin(
          id: 'installed@local',
          name: 'Installed plugin',
          marketplaceName: 'local',
          installed: true,
          enabled: true,
        ),
      );
    final controller = CodexController(pluginStore: pluginStore);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();

    expect(find.text('Installed plugin'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('manages Codex marketplaces and uninstalls plugins', () async {
    const marketplace = CodexMarketplace(
      name: 'team-tools',
      root: '/plugins/team-tools',
      sourceType: 'git',
      source: 'example-org/team-tools',
    );
    final pluginStore = MemoryCodexPluginStore()
      ..plugins.add(
        const CodexPlugin(
          id: 'sample@team-tools',
          name: 'sample',
          marketplaceName: 'team-tools',
          installed: true,
          enabled: true,
        ),
      )
      ..marketplaces.add(marketplace);
    final controller = CodexController(pluginStore: pluginStore);

    await controller.refreshPlugins();
    await controller.refreshMarketplaces();
    await controller.addPluginMarketplace('example-org/new-tools');
    await controller.upgradePluginMarketplace('team-tools');
    await controller.removePlugin(controller.plugins.single);
    await controller.removePluginMarketplace(marketplace);

    expect(pluginStore.addedMarketplaces, ['example-org/new-tools']);
    expect(pluginStore.upgradedMarketplaceNames, ['team-tools']);
    expect(pluginStore.removedPluginIds, ['sample@team-tools']);
    expect(pluginStore.removedMarketplaceNames, ['team-tools']);
    controller.dispose();
  });

  test('ignores older plugin and marketplace refresh results', () async {
    const olderPlugin = CodexPlugin(
      id: 'older@local',
      name: 'older',
      marketplaceName: 'local',
      installed: true,
      enabled: true,
    );
    const newerPlugin = CodexPlugin(
      id: 'newer@local',
      name: 'newer',
      marketplaceName: 'local',
      installed: true,
      enabled: true,
    );
    const olderMarketplace = CodexMarketplace(
      name: 'older',
      root: '/plugins/older',
      sourceType: 'git',
      source: 'example/older',
    );
    const newerMarketplace = CodexMarketplace(
      name: 'newer',
      root: '/plugins/newer',
      sourceType: 'git',
      source: 'example/newer',
    );
    final store = BlockingExtensionListCodexPluginStore();
    final controller = CodexController(pluginStore: store);

    final olderPlugins = controller.refreshPlugins();
    final newerPlugins = controller.refreshPlugins();
    expect(store.pluginRequests, hasLength(2));
    store.pluginRequests.last.complete([newerPlugin]);
    await newerPlugins;
    store.pluginRequests.first.complete([olderPlugin]);
    await olderPlugins;

    final olderMarketplaces = controller.refreshMarketplaces();
    final newerMarketplaces = controller.refreshMarketplaces();
    expect(store.marketplaceRequests, hasLength(2));
    store.marketplaceRequests.last.complete([newerMarketplace]);
    await newerMarketplaces;
    store.marketplaceRequests.first.complete([olderMarketplace]);
    await olderMarketplaces;

    expect(controller.plugins, [newerPlugin]);
    expect(controller.marketplaces, [newerMarketplace]);
    expect(controller.pluginsLoading, isFalse);
    expect(controller.marketplacesLoading, isFalse);
    controller.dispose();
  });

  test(
    'reports plugin progress, completion, and restart requirement',
    () async {
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: false,
        enabled: false,
      );
      final pluginStore = BlockingCodexPluginStore()..plugins.add(plugin);
      final controller = CodexController(pluginStore: pluginStore);

      final install = controller.installPlugin(plugin);
      await Future<void>.delayed(Duration.zero);

      expect(controller.pluginSaving, isTrue);
      expect(controller.pluginActionTargetId, plugin.id);
      expect(controller.pluginActionProgress, '正在安装插件 sample…');
      expect(controller.pluginRuntimeRestartRequired, isFalse);
      expect(controller.canChooseWorkspace, isFalse);
      expect(controller.canChangePrimaryWorkspace, isFalse);
      expect(controller.changePrimaryWorkspaceDisabledReason, '请等待扩展配置更新完成。');

      pluginStore.installCompleter.complete();
      await install;

      expect(controller.pluginSaving, isFalse);
      expect(controller.pluginActionProgress, isNull);
      expect(controller.pluginActionResult, contains('重启运行时'));
      expect(controller.pluginRuntimeRestartRequired, isTrue);
      expect(controller.canChooseWorkspace, isTrue);
      expect(controller.canChangePrimaryWorkspace, isTrue);
      expect(controller.changePrimaryWorkspaceDisabledReason, isNull);
      controller.dispose();
    },
  );

  test(
    'automatically reconnects after a plugin configuration change',
    () async {
      final primary = await Directory.systemTemp.createTemp(
        'codex-desk-plugin-reconnect-',
      );
      addTearDown(() => primary.delete(recursive: true));
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: false,
        enabled: false,
      );
      final pluginStore = MemoryCodexPluginStore()..plugins.add(plugin);
      final server = ManagedRuntimeFakeServer()
        ..listResponse = [
          {'id': 'connected-thread', 'preview': 'connected'},
        ];
      final controller = CodexController(
        server: server,
        pluginStore: pluginStore,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      await controller.selectWorkspaceAndReconnect(primary.path);

      await controller.installPlugin(plugin);

      expect(server.stopCalls, 1);
      expect(server.startCalls, 2);
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.pluginRuntimeRestartRequired, isFalse);
      expect(controller.pluginActionResult, contains('运行时已重启'));
      controller.dispose();
    },
  );

  test('keeps the plugin CLI failure reason in action feedback', () async {
    const plugin = CodexPlugin(
      id: 'sample@local',
      name: 'sample',
      marketplaceName: 'local',
      installed: false,
      enabled: false,
    );
    final controller = CodexController(
      pluginStore: FailingCodexPluginStore()..plugins.add(plugin),
    );

    await controller.installPlugin(plugin);

    expect(controller.pluginsError, contains('安装插件 sample失败'));
    expect(controller.pluginsError, contains('marketplace 无法访问'));
    expect(controller.pluginRuntimeRestartRequired, isFalse);
    controller.dispose();
  });

  test(
    'keeps a pending restart notice when a later plugin action fails',
    () async {
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: false,
        enabled: false,
      );
      final controller = CodexController(
        pluginStore: FailOnSecondInstallCodexPluginStore()..plugins.add(plugin),
      );

      await controller.installPlugin(plugin);
      final pendingRestartNotice = controller.pluginActionResult;
      await controller.installPlugin(plugin);

      expect(controller.pluginsError, contains('second install failed'));
      expect(controller.pluginRuntimeRestartRequired, isTrue);
      expect(controller.pluginActionResult, pendingRestartNotice);
      expect(controller.pluginActionResult, contains('重启运行时'));
      controller.dispose();
    },
  );

  test('rejects malformed plugin list JSON from the Codex CLI', () async {
    final store = CodexPluginStore(
      executableProvider: () => 'codex-test',
      processRunner: (executable, arguments) async =>
          ProcessResult(1, 0, '{"installed":"invalid","available":[]}', ''),
    );

    await expectLater(store.listPlugins(), throwsFormatException);
  });

  test('rejects plugin logos that resolve outside the plugin source', () async {
    final root = await Directory.systemTemp.createTemp('codex-plugin-logo-');
    addTearDown(() => root.delete(recursive: true));
    final source = Directory('${root.path}/plugin')..createSync();
    final manifestDirectory = Directory('${source.path}/.codex-plugin')
      ..createSync();
    await File('${root.path}/outside.png').writeAsBytes(const [1, 2, 3]);
    await File('${manifestDirectory.path}/plugin.json').writeAsString(
      jsonEncode({
        'interface': {'logo': '../outside.png'},
      }),
    );
    final store = CodexPluginStore(
      executableProvider: () => 'codex-test',
      processRunner: (executable, arguments) async => ProcessResult(
        0,
        0,
        jsonEncode({
          'installed': [
            {
              'pluginId': 'sample@local',
              'name': 'sample',
              'installed': true,
              'enabled': true,
              'source': {'path': source.path},
            },
          ],
          'available': [],
        }),
        '',
      ),
    );

    final plugin = (await store.listPlugins()).single;
    expect(plugin.logoPath, isNull);
  });

  test('resolves the CLI path before running plugin commands', () async {
    const resolvedPath = '/Applications/ChatGPT.app/Contents/Resources/codex';
    String? launchedExecutable;
    final store = CodexPluginStore(
      executableProvider: () async => resolvedPath,
      processRunner: (executable, arguments) async {
        launchedExecutable = executable;
        return ProcessResult(1, 0, '{"installed":[],"available":[]}', '');
      },
    );

    await store.listPlugins();

    expect(launchedExecutable, resolvedPath);
  });

  test('preserves Codex CLI stderr when a plugin command fails', () async {
    const plugin = CodexPlugin(
      id: 'sample@local',
      name: 'sample',
      marketplaceName: 'local',
      installed: false,
      enabled: false,
    );
    final store = CodexPluginStore(
      executableProvider: () => 'codex-test',
      processRunner: (executable, arguments) async =>
          ProcessResult(1, 9, '', 'marketplace signature invalid'),
    );

    await expectLater(
      store.installPlugin(plugin),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'marketplace signature invalid',
        ),
      ),
    );
  });

  test('lists MCP servers from Codex CLI JSON', () async {
    final codexHome = await Directory.systemTemp.createTemp(
      'codex-mcp-managed-home-',
    );
    addTearDown(() => codexHome.delete(recursive: true));
    final store = CodexPluginStore(
      codexHome: codexHome,
      executableProvider: () => 'codex-test',
      processRunner: (executable, arguments) async => ProcessResult(
        1,
        0,
        '[{"name":"figma","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.figma.com/mcp"},"auth_status":"unknown"}]',
        '',
      ),
    );

    final servers = await store.listMcpServers();

    expect(servers.single.name, 'figma');
    expect(servers.single.enabled, isTrue);
    expect(servers.single.transportLabel, 'https://mcp.figma.com/mcp');
    expect(servers.single.scope, CodexMcpServerScope.managed);
  });

  test('ignores an older MCP refresh after the workspace changes', () async {
    final store = BlockingMcpListCodexPluginStore();
    final controller = CodexController(
      server: FakeCodexAppServer(),
      pluginStore: store,
    )..workspacePath = '/workspace-a';

    final firstRefresh = controller.refreshMcpServers();
    expect(store.requests.single.workspace, '/workspace-a');

    controller.workspacePath = '/workspace-b';
    final secondRefresh = controller.refreshMcpServers();
    expect(store.requests.last.workspace, '/workspace-b');
    store.requests.last.completer.complete(const [
      CodexMcpServer(
        name: 'workspace-b-server',
        enabled: true,
        transportLabel: 'https://b.example/mcp',
      ),
    ]);
    await secondRefresh;

    store.requests.first.completer.complete(const [
      CodexMcpServer(
        name: 'workspace-a-server',
        enabled: true,
        transportLabel: 'https://a.example/mcp',
      ),
    ]);
    await firstRefresh;

    expect(controller.mcpServers.single.name, 'workspace-b-server');
    expect(controller.mcpServersLoading, isFalse);
    controller.dispose();
  });

  test('lists MCP servers from the selected workspace directory', () async {
    final codexHome = await Directory.systemTemp.createTemp(
      'codex-mcp-list-home-',
    );
    final workspace = await Directory.systemTemp.createTemp(
      'codex-mcp-list-workspace-',
    );
    addTearDown(() async {
      await codexHome.delete(recursive: true);
      await workspace.delete(recursive: true);
    });
    await File(
      '${codexHome.path}/config.toml',
    ).writeAsString('[mcp_servers.figma]\nurl = "https://mcp.figma.com/mcp"\n');
    String? launchedDirectory;
    final store = CodexPluginStore(
      codexHome: codexHome,
      executableProvider: () => 'codex-test',
      scopedProcessRunner: (executable, arguments, workingDirectory) async {
        launchedDirectory = workingDirectory;
        return ProcessResult(
          1,
          0,
          '[{"name":"figma","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.figma.com/mcp"}}]',
          '',
        );
      },
    );

    final servers = await store.listMcpServers(
      workingDirectory: workspace.path,
    );

    expect(launchedDirectory, workspace.path);
    expect(servers.single.scope, CodexMcpServerScope.user);
    expect(servers.single.configurationPath, '${codexHome.path}/config.toml');
  });

  test('attributes a trusted project MCP server to its project config', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-trusted-project-mcp-list-',
    );
    addTearDown(() => root.delete(recursive: true));
    final codexHome = Directory('${root.path}/home/.codex');
    final workspace = Directory('${root.path}/workspace');
    final projectConfig = File('${workspace.path}/.codex/config.toml');
    final userConfig = File('${codexHome.path}/config.toml');
    await projectConfig.parent.create(recursive: true);
    await userConfig.parent.create(recursive: true);
    await projectConfig.writeAsString(
      '[mcp_servers.figma]\n'
      'url = "https://mcp.figma.com/mcp"\n',
    );
    await userConfig.writeAsString(
      '[projects."${workspace.path}"]\ntrust_level = "trusted"\n',
    );
    final store = CodexPluginStore(
      codexHome: codexHome,
      executableProvider: () => 'codex-test',
      scopedProcessRunner: (executable, arguments, workingDirectory) async =>
          ProcessResult(
            1,
            0,
            '[{"name":"figma","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.figma.com/mcp"}}]',
            '',
          ),
    );

    final server = (await store.listMcpServers(
      workingDirectory: workspace.path,
    )).single;

    expect(server.scope, CodexMcpServerScope.project);
    expect(server.configurationPath, projectConfig.path);
  });

  test(
    'recognizes literal quoted MCP and project tables when updating scopes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-literal-quoted-mcp-',
      );
      addTearDown(() => root.delete(recursive: true));
      final codexHome = Directory('${root.path}/home/.codex');
      final workspace = Directory('${root.path}/workspace');
      final projectConfig = File('${workspace.path}/.codex/config.toml');
      final userConfig = File('${codexHome.path}/config.toml');
      await projectConfig.parent.create(recursive: true);
      await userConfig.parent.create(recursive: true);
      await projectConfig.writeAsString(
        "[mcp_servers.'docs.prod']\n"
        "url = 'https://project.example/mcp'\n"
        'enabled = true\n',
      );
      await userConfig.writeAsString(
        "[projects.'${workspace.path}']\n"
        "trust_level = 'trusted'\n\n"
        "[mcp_servers.'user.docs']\n"
        "url = 'https://user.example/mcp'\n"
        'enabled = true\n',
      );
      final store = CodexPluginStore(
        codexHome: codexHome,
        executableProvider: () => 'codex-test',
        scopedProcessRunner: (executable, arguments, workingDirectory) async =>
            ProcessResult(
              1,
              0,
              '[{"name":"docs.prod","enabled":true,"transport":{"type":"streamable_http","url":"https://project.example/mcp"}},'
                  '{"name":"user.docs","enabled":true,"transport":{"type":"streamable_http","url":"https://user.example/mcp"}}]',
              '',
            ),
      );

      final servers = await store.listMcpServers(
        workingDirectory: workspace.path,
      );
      final projectServer = servers.singleWhere(
        (server) => server.name == 'docs.prod',
      );
      final userServer = servers.singleWhere(
        (server) => server.name == 'user.docs',
      );
      expect(projectServer.scope, CodexMcpServerScope.project);
      expect(projectServer.configurationPath, projectConfig.path);
      expect(userServer.scope, CodexMcpServerScope.user);
      expect(userServer.configurationPath, userConfig.path);

      await store.setMcpServerEnabled(
        projectServer,
        false,
        workingDirectory: workspace.path,
      );
      await store.setMcpServerEnabled(
        userServer,
        false,
        workingDirectory: workspace.path,
      );

      expect(
        await projectConfig.readAsString(),
        "[mcp_servers.'docs.prod']\n"
        "url = 'https://project.example/mcp'\n"
        'enabled = false\n',
      );
      expect(
        await userConfig.readAsString(),
        "[projects.'${workspace.path}']\n"
        "trust_level = 'trusted'\n\n"
        "[mcp_servers.'user.docs']\n"
        "url = 'https://user.example/mcp'\n"
        'enabled = false\n',
      );
    },
  );

  test('updates a project-scoped MCP server in its defining config', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-project-mcp-config-',
    );
    addTearDown(() => root.delete(recursive: true));
    final codexHome = Directory('${root.path}/home/.codex');
    final workspace = Directory('${root.path}/workspace');
    final projectConfig = File('${workspace.path}/.codex/config.toml');
    final userConfig = File('${codexHome.path}/config.toml');
    await projectConfig.parent.create(recursive: true);
    await userConfig.parent.create(recursive: true);
    await projectConfig.writeAsString(
      '[mcp_servers.figma]\n'
      'url = "https://mcp.figma.com/mcp"\n'
      'enabled = true\n',
    );
    await userConfig.writeAsString(
      '[projects."${workspace.path}"]\n'
      'trust_level = "trusted"\n\n'
      '[mcp_servers.docs]\n'
      'url = "https://developers.openai.com/mcp"\n',
    );
    final originalUserConfig = await userConfig.readAsString();

    await CodexPluginStore(codexHome: codexHome).setMcpServerEnabled(
      const CodexMcpServer(
        name: 'figma',
        enabled: true,
        transportLabel: 'https://mcp.figma.com/mcp',
      ),
      false,
      workingDirectory: workspace.path,
    );

    expect(await projectConfig.readAsString(), contains('enabled = false'));
    expect(await userConfig.readAsString(), originalUserConfig);
  });

  test(
    'does not attribute a user MCP server to an untrusted project config',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-untrusted-project-mcp-',
      );
      addTearDown(() => root.delete(recursive: true));
      final codexHome = Directory('${root.path}/home/.codex');
      final workspace = Directory('${root.path}/workspace');
      final projectConfig = File('${workspace.path}/.codex/config.toml');
      final userConfig = File('${codexHome.path}/config.toml');
      await projectConfig.parent.create(recursive: true);
      await userConfig.parent.create(recursive: true);
      await projectConfig.writeAsString(
        '[mcp_servers.figma]\n'
        'url = "https://untrusted.example/mcp"\n'
        'enabled = true\n',
      );
      await userConfig.writeAsString(
        '[mcp_servers.figma]\n'
        'url = "https://mcp.figma.com/mcp"\n'
        'enabled = true\n',
      );
      final store = CodexPluginStore(
        codexHome: codexHome,
        executableProvider: () => 'codex-test',
        scopedProcessRunner: (executable, arguments, workingDirectory) async =>
            ProcessResult(
              1,
              0,
              '[{"name":"figma","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.figma.com/mcp"}}]',
              '',
            ),
      );

      final server = (await store.listMcpServers(
        workingDirectory: workspace.path,
      )).single;
      expect(server.scope, CodexMcpServerScope.user);

      await store.setMcpServerEnabled(
        server,
        false,
        workingDirectory: workspace.path,
      );

      expect(await userConfig.readAsString(), contains('enabled = false'));
      expect(await projectConfig.readAsString(), contains('enabled = true'));
    },
  );

  test('refuses to update a project MCP server without a workspace', () async {
    final codexHome = await Directory.systemTemp.createTemp(
      'codex-project-mcp-missing-workspace-',
    );
    addTearDown(() => codexHome.delete(recursive: true));
    final config = File('${codexHome.path}/config.toml');
    await config.writeAsString(
      '[mcp_servers.figma]\nurl = "https://mcp.figma.com/mcp"\n',
    );

    await expectLater(
      CodexPluginStore(codexHome: codexHome).setMcpServerEnabled(
        const CodexMcpServer(
          name: 'figma',
          enabled: true,
          transportLabel: 'https://mcp.figma.com/mcp',
          scope: CodexMcpServerScope.project,
        ),
        false,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('缺少当前项目目录'),
        ),
      ),
    );
    expect(await config.readAsString(), isNot(contains('enabled')));
  });

  test(
    'updates MCP and skill enabled state without duplicating tables',
    () async {
      final codexHome = await Directory.systemTemp.createTemp(
        'codex-extension-config-',
      );
      addTearDown(() => codexHome.delete(recursive: true));
      final config = File('${codexHome.path}/config.toml');
      await config.writeAsString(
        '[mcp_servers.figma]\n'
        'url = "https://mcp.figma.com/mcp"\n'
        'enabled = true\n\n'
        '[[skills.config]]\n'
        'path = "/skills/review/SKILL.md"\n\n'
        '[features]\n'
        'web_search = true\n',
      );
      final store = CodexPluginStore(codexHome: codexHome);

      await store.setMcpServerEnabled(
        const CodexMcpServer(
          name: 'figma',
          enabled: true,
          transportLabel: 'https://mcp.figma.com/mcp',
        ),
        false,
      );
      await store.setSkillEnabled(
        const CodexSkill(
          name: 'review',
          path: '/skills/review/SKILL.md',
          description: 'Review code',
          enabled: true,
          scope: 'user',
        ),
        false,
      );

      final updated = await config.readAsString();
      expect(
        RegExp(
          r'^\[mcp_servers\.figma\]$',
          multiLine: true,
        ).allMatches(updated),
        hasLength(1),
      );
      expect(
        RegExp(
          r'^\[\[skills\.config\]\]$',
          multiLine: true,
        ).allMatches(updated),
        hasLength(1),
      );
      expect(
        RegExp(r'^enabled = false$', multiLine: true).allMatches(updated),
        hasLength(2),
      );
      expect(
        updated.indexOf(
          'enabled = false',
          updated.indexOf('[[skills.config]]'),
        ),
        lessThan(updated.indexOf('[features]')),
      );
    },
  );

  test(
    'updates a literal quoted skill path without duplicating its block',
    () async {
      final codexHome = await Directory.systemTemp.createTemp(
        'codex-literal-skill-config-',
      );
      addTearDown(() => codexHome.delete(recursive: true));
      final config = File('${codexHome.path}/config.toml');
      await config.writeAsString(
        '[[skills.config]] # keep this comment\n'
        "path = '/skills/review/SKILL.md' # literal path\n"
        'description = "Review code"\n'
        'enabled = true # current state\n\n'
        '[features]\n'
        'web_search = true\n',
      );

      await CodexPluginStore(codexHome: codexHome).setSkillEnabled(
        const CodexSkill(
          name: 'review',
          path: '/skills/review/SKILL.md',
          description: 'Review code',
          enabled: true,
          scope: 'user',
        ),
        false,
      );

      final updated = await config.readAsString();
      expect(
        RegExp(r'^\[\[skills\.config\]\]', multiLine: true).allMatches(updated),
        hasLength(1),
      );
      expect(
        updated,
        contains("path = '/skills/review/SKILL.md' # literal path"),
      );
      expect(updated, contains('description = "Review code"'));
      expect(updated, contains('enabled = false # current state'));
    },
  );

  test(
    'writes only the selected plugin enabled state to Codex config',
    () async {
      final codexHome = await Directory.systemTemp.createTemp('codex-config-');
      addTearDown(() => codexHome.delete(recursive: true));
      final config = File('${codexHome.path}/config.toml');
      await config.writeAsString(
        'model = "gpt-5"\n\n'
        '[plugins."sample@local"] # 本地测试插件\n'
        'enabled = true # 需要保留的说明\n\n'
        '[features]\n'
        'web_search = true\n',
      );
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: true,
        enabled: true,
      );

      await CodexPluginStore(
        codexHome: codexHome,
      ).setPluginEnabled(plugin, false);

      expect(
        await config.readAsString(),
        'model = "gpt-5"\n\n'
        '[plugins."sample@local"] # 本地测试插件\n'
        'enabled = false # 需要保留的说明\n\n'
        '[features]\n'
        'web_search = true\n',
      );
    },
  );

  test(
    'creates a missing Codex config directory with an atomic plugin update',
    () async {
      final root = await Directory.systemTemp.createTemp('codex-config-root-');
      addTearDown(() => root.delete(recursive: true));
      final codexHome = Directory('${root.path}/missing/.codex');
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: true,
        enabled: false,
      );

      await CodexPluginStore(
        codexHome: codexHome,
      ).setPluginEnabled(plugin, true);

      final config = File('${codexHome.path}/config.toml');
      expect(
        await config.readAsString(),
        '[plugins."sample@local"]\nenabled = true\n',
      );
      expect(
        await codexHome
            .list()
            .where((entry) => entry.path.contains('.tmp-'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test('preserves a symlinked Codex config when updating a plugin', () async {
    final root = await Directory.systemTemp.createTemp('codex-config-link-');
    addTearDown(() => root.delete(recursive: true));
    final target = File('${root.path}/managed/config.toml');
    await target.parent.create(recursive: true);
    await target.writeAsString('[plugins."sample@local"]\nenabled = false\n');
    final codexHome = Directory('${root.path}/.codex');
    await codexHome.create();
    final configLink = Link('${codexHome.path}/config.toml');
    await configLink.create(target.path);
    const plugin = CodexPlugin(
      id: 'sample@local',
      name: 'sample',
      marketplaceName: 'local',
      installed: true,
      enabled: false,
    );

    await CodexPluginStore(codexHome: codexHome).setPluginEnabled(plugin, true);

    expect(
      await FileSystemEntity.type(configLink.path, followLinks: false),
      FileSystemEntityType.link,
    );
    expect(await target.readAsString(), contains('enabled = true'));
  });

  testWidgets('opens the local Codex plugin manager', (tester) async {
    final pluginStore = MemoryCodexPluginStore()
      ..plugins.add(
        const CodexPlugin(
          id: 'sample@local',
          name: 'Sample plugin',
          marketplaceName: 'local',
          installed: true,
          enabled: true,
        ),
      );
    final controller = CodexController(pluginStore: pluginStore);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('plugin-manager-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plugin-manager-dialog')), findsOneWidget);
    expect(find.text('Sample plugin'), findsOneWidget);
  });

  testWidgets('opens plugin settings tabs from the plugin page gear', (
    tester,
  ) async {
    final pluginStore = MemoryCodexPluginStore()
      ..plugins.add(
        const CodexPlugin(
          id: 'documents@openai',
          name: 'Documents',
          marketplaceName: 'openai',
          installed: true,
          enabled: true,
          description: 'Create and edit documents',
        ),
      )
      ..mcpServers.add(
        const CodexMcpServer(
          name: 'figma',
          enabled: true,
          transportLabel: 'https://mcp.figma.com/mcp',
        ),
      );
    final server = FakeCodexAppServer()
      ..skillListResponse = const [
        {
          'name': 'code-review',
          'path': '/skills/code-review/SKILL.md',
          'description': 'Review code changes',
          'enabled': true,
          'scope': 'user',
          'interface': {'displayName': '代码审查'},
        },
      ];
    final controller = CodexController(server: server, pluginStore: pluginStore)
      ..workspacePath = '/workspace';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-settings-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plugin-manager-dialog')), findsOneWidget);
    expect(find.text('插件  1'), findsOneWidget);
    expect(find.text('MCP  1'), findsOneWidget);
    expect(find.text('技能  1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('plugin-manager-dialog')),
        matching: find.text('Documents'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings-mcp-tab')));
    await tester.pumpAndSettle();
    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('figma'), findsOneWidget);
    expect(find.byKey(const Key('add-mcp-server-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-skills-tab')));
    await tester.pumpAndSettle();
    expect(find.text('代码审查'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('plugin-manager-dialog')),
        matching: find.text('个人'),
      ),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(const Size(700, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pump();
    expect(find.byKey(const Key('extension-settings-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows MCP action failures in the MCP settings tab', (
    tester,
  ) async {
    final pluginStore = FailingMcpCodexPluginStore()
      ..mcpServers.add(
        const CodexMcpServer(
          name: 'figma',
          enabled: true,
          transportLabel: 'https://mcp.figma.com/mcp',
        ),
      );
    final controller = CodexController(pluginStore: pluginStore)
      ..workspacePath = '/workspace';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('plugin-manager-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-mcp-tab')));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-mcp-figma'));
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plugin-action-error')), findsOneWidget);
    expect(find.textContaining('MCP 配置不可写'), findsOneWidget);
  });

  testWidgets('keeps MCP add failures visible and prevents silent dismissal', (
    tester,
  ) async {
    final controller = CodexController(
      pluginStore: FailingMcpCodexPluginStore(),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('plugin-manager-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-mcp-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-mcp-server-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mcp-server-name-field')),
      'figma',
    );
    await tester.enterText(
      find.byKey(const Key('mcp-server-url-field')),
      'https://mcp.figma.com/mcp',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit-mcp-server-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-mcp-server-dialog')), findsOneWidget);
    expect(find.byKey(const Key('add-mcp-server-error')), findsOneWidget);
    expect(find.textContaining('MCP 配置不可写'), findsWidgets);
  });

  testWidgets(
    'closes a successful MCP add when only the extension refresh warns',
    (tester) async {
      final pluginStore = McpAddWithRefreshWarningCodexPluginStore();
      final controller = CodexController(pluginStore: pluginStore);
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      await tester.tap(find.byKey(const Key('plugin-manager-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-mcp-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-mcp-server-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('mcp-server-name-field')),
        'figma',
      );
      await tester.enterText(
        find.byKey(const Key('mcp-server-url-field')),
        'https://mcp.figma.com/mcp',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-mcp-server-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-mcp-server-dialog')), findsNothing);
      expect(find.byKey(const Key('plugin-action-warning')), findsOneWidget);
      expect(find.byKey(const Key('plugin-action-error')), findsNothing);
      expect(find.textContaining('操作已完成'), findsOneWidget);
      expect(find.textContaining('MCP 列表暂时不可用'), findsOneWidget);
      expect(controller.pluginActionError, isNull);
      expect(pluginStore.mcpServers.single.name, 'figma');
    },
  );

  testWidgets('uninstalls an installed plugin from extension settings', (
    tester,
  ) async {
    const plugin = CodexPlugin(
      id: 'documents@openai',
      name: 'Documents',
      marketplaceName: 'openai',
      installed: true,
      enabled: true,
    );
    final pluginStore = MemoryCodexPluginStore()..plugins.add(plugin);
    final controller = CodexController(pluginStore: pluginStore);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('plugin-manager-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('remove-plugin-documents@openai')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remove-plugin-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-remove-plugin-button')));
    await tester.pumpAndSettle();

    expect(pluginStore.removedPluginIds, ['documents@openai']);
    expect(
      find.byKey(const ValueKey('settings-plugin-documents@openai')),
      findsNothing,
    );
  });

  testWidgets('shows plugin progress and restart feedback in the manager', (
    tester,
  ) async {
    const plugin = CodexPlugin(
      id: 'available@local',
      name: 'Available plugin',
      marketplaceName: 'local',
      installed: true,
      enabled: true,
    );
    final pluginStore = BlockingCodexPluginStore()..plugins.add(plugin);
    final controller = CodexController(pluginStore: pluginStore);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('plugin-manager-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(find.byKey(const Key('plugin-action-progress')), findsOneWidget);
    expect(find.byKey(const Key('plugin-tile-progress')), findsOneWidget);

    pluginStore.enabledCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plugin-action-result')), findsOneWidget);
    expect(find.textContaining('重启运行时'), findsWidgets);
  });

  testWidgets('switches plugin library tabs and starts plugin or skill flows', (
    tester,
  ) async {
    final server = FakeCodexAppServer()
      ..skillListResponse = const [
        {
          'name': 'skill-creator',
          'path': '/skills/skill-creator/SKILL.md',
          'description': 'Create reusable skills',
          'enabled': true,
          'scope': 'system',
          'interface': {
            'displayName': 'Skill Creator',
            'shortDescription': 'Create a reusable Codex skill',
          },
        },
      ];
    final controller =
        CodexController(server: server, pluginStore: MemoryCodexPluginStore())
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-skills-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skills-page')), findsOneWidget);
    expect(find.text('Skill Creator'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plugins-tab')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建插件'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .text,
      r'$plugin-creator help me create a plugin',
    );

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('录制技能'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('composer-record-skill-chip')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens the marketplace source form from plugin add menu', (
    tester,
  ) async {
    final server = FakeCodexAppServer();
    final controller =
        CodexController(server: server, pluginStore: MemoryCodexPluginStore())
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加插件市场'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-marketplace-dialog')), findsOneWidget);
    expect(find.byKey(const Key('marketplace-source-field')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('opens plugin management inside the settings content pane', (
    tester,
  ) async {
    final controller = CodexController(
      server: FakeCodexAppServer(),
      pluginStore: MemoryCodexPluginStore(),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );

    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-nav-插件')),
      240,
      scrollable: find.descendant(
        of: find.byKey(const Key('settings-navigation-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('settings-nav-插件')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-plugins-page')), findsOneWidget);
    expect(find.byKey(const Key('settings-navigation-pane')), findsOneWidget);
    expect(find.byKey(const Key('plugin-manager-dialog')), findsNothing);
    expect(find.text('管理已安装插件、MCP 服务器和可用技能。'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(700, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pump();
    expect(find.byKey(const Key('extension-settings-search')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('labels cached MCP rows when refresh fails', (tester) async {
    final server = FakeCodexAppServer()
      ..mcpServerStatusError = StateError('连接失败');
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..runtimeMcpServerStatuses = const [
        CodexMcpRuntimeStatus(
          name: 'cached-server',
          authStatus: 'unknown',
          runtimeStatus: 'connected',
          toolCount: 0,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/m');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('cached-server'), findsOneWidget);
    expect(find.textContaining('以下为上次读取的结果。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
