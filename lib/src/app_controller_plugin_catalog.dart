import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/codex_plugin_store.dart';

/// 集中读取插件、marketplace、MCP 与 Skill 目录，不拥有加载状态或写入状态。
/// Centralizes plugin, marketplace, MCP, and Skill catalog reads without owning loading or mutation state.
class CodexPluginCatalog {
  CodexPluginCatalog({
    required CodexPluginStore pluginStore,
    required CodexAppServer server,
  }) : _pluginStore = pluginStore,
       _server = server;

  final CodexPluginStore _pluginStore;
  final CodexAppServer _server;

  /// 从本机 Codex CLI 读取已安装和可用插件。
  /// Reads installed and available plugins from the local Codex CLI.
  Future<List<CodexPlugin>> listPlugins() => _pluginStore.listPlugins();

  /// 从本机 Codex CLI 读取已配置的 marketplace 来源。
  /// Reads configured marketplace sources from the local Codex CLI.
  Future<List<CodexMarketplace>> listMarketplaces() =>
      _pluginStore.listMarketplaces();

  /// 读取指定项目目录的 MCP 服务器。
  /// Reads MCP servers for the requested project directory.
  Future<List<CodexMcpServer>> listMcpServers({String? workingDirectory}) =>
      _pluginStore.listMcpServers(workingDirectory: workingDirectory);

  /// 从 App Server 读取并解析当前工作区公布的 Skill。
  /// Reads and parses the Skills advertised by App Server.
  Future<List<CodexSkill>> listSkills({
    required String workingDirectory,
    bool forceReload = false,
  }) async {
    final rows = await _server.listSkills(
      workingDirectory: workingDirectory,
      forceReload: forceReload,
    );
    return rows
        .map(CodexSkill.fromJson)
        .whereType<CodexSkill>()
        .toList(growable: false);
  }
}
