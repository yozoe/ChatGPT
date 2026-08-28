// Test double extracted from widget_test.dart.
import 'dart:async';
import 'dart:math' as math;
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/domain/scheduled_task.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/codex_plugin_store.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:chatgpt/src/services/local_session_thread_store.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';

class MemoryCodexPluginStore extends CodexPluginStore {
  final plugins = <CodexPlugin>[];
  final mcpServers = <CodexMcpServer>[];
  final addedMarketplaces = <String>[];
  final marketplaces = <CodexMarketplace>[];
  final installedPluginIds = <String>[];
  final removedPluginIds = <String>[];
  final upgradedMarketplaceNames = <String?>[];
  final removedMarketplaceNames = <String>[];
  final enabledChanges = <String, bool>{};
  String? listedMcpWorkingDirectory;
  String? updatedMcpWorkingDirectory;
  Object? mcpListError;

  /// 从测试内存列表返回已安装与可安装插件。
  /// Returns installed and available plugins from the test memory list.
  @override
  Future<List<CodexPlugin>> listPlugins() async => List.of(plugins);

  @override
  Future<List<CodexMcpServer>> listMcpServers({
    String? workingDirectory,
  }) async {
    listedMcpWorkingDirectory = workingDirectory;
    if (mcpListError case final error?) throw error;
    return List.of(mcpServers);
  }

  @override
  Future<void> addMcpServer({required String name, required String url}) async {
    mcpServers.add(
      CodexMcpServer(name: name, enabled: true, transportLabel: url),
    );
  }

  @override
  Future<void> setMcpServerEnabled(
    CodexMcpServer server,
    bool enabled, {
    String? workingDirectory,
  }) async {
    updatedMcpWorkingDirectory = workingDirectory;
    final index = mcpServers.indexWhere((value) => value.name == server.name);
    if (index >= 0) mcpServers[index] = server.copyWith(enabled: enabled);
  }

  @override
  Future<void> setSkillEnabled(CodexSkill skill, bool enabled) async {}

  /// 记录添加的本地 marketplace，供控制器行为断言。
  /// Records a local marketplace addition for controller behavior assertions.
  @override
  Future<void> addLocalMarketplace(String directory) async {
    addedMarketplaces.add(directory);
  }

  /// 记录本地或远程 marketplace 来源，供控制器行为断言。
  /// Records a local or remote marketplace source for controller behavior assertions.
  @override
  Future<void> addMarketplace(String source) async {
    addedMarketplaces.add(source);
  }

  /// 从测试内存列表返回 marketplace 来源。
  /// Returns marketplace sources from the test memory list.
  @override
  Future<List<CodexMarketplace>> listMarketplaces() async =>
      List.of(marketplaces);

  /// 记录 marketplace 更新请求。
  /// Records a marketplace upgrade request.
  @override
  Future<void> upgradeMarketplace(String? name) async {
    upgradedMarketplaceNames.add(name);
  }

  /// 记录被移除的 marketplace 名称。
  /// Records the name of a removed marketplace.
  @override
  Future<void> removeMarketplace(CodexMarketplace marketplace) async {
    removedMarketplaceNames.add(marketplace.name);
  }

  /// 记录待安装插件，并将其状态改为已安装。
  /// Records a plugin installation and changes its state to installed.
  @override
  Future<void> installPlugin(CodexPlugin plugin) async {
    installedPluginIds.add(plugin.id);
    final index = plugins.indexWhere((value) => value.id == plugin.id);
    if (index >= 0) {
      plugins[index] = CodexPlugin(
        id: plugin.id,
        name: plugin.name,
        marketplaceName: plugin.marketplaceName,
        installed: true,
        enabled: true,
        version: plugin.version,
        installPolicy: plugin.installPolicy,
        authPolicy: plugin.authPolicy,
        description: plugin.description,
      );
    }
  }

  /// 记录待卸载插件，并从测试内存列表中移除它。
  /// Records a plugin removal and removes it from the test memory list.
  @override
  Future<void> removePlugin(CodexPlugin plugin) async {
    removedPluginIds.add(plugin.id);
    plugins.removeWhere((value) => value.id == plugin.id);
  }

  /// 记录插件启用状态，并同步测试内存列表。
  /// Records a plugin enabled state and synchronizes the test memory list.
  @override
  Future<void> setPluginEnabled(CodexPlugin plugin, bool enabled) async {
    enabledChanges[plugin.id] = enabled;
    final index = plugins.indexWhere((value) => value.id == plugin.id);
    if (index >= 0) plugins[index] = plugins[index].copyWith(enabled: enabled);
  }
}
// ignore_for_file: unused_import, unnecessary_import
