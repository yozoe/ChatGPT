import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/codex_mcp_runtime_status.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';

/// Owns plugin, Skill, marketplace, and MCP catalog presentation state.
///
/// The controller still coordinates CLI/App Server requests, refresh epochs,
/// configuration writes, reconnects, and notifications. This state groups the
/// mutable catalog snapshots and their loading/error/action feedback so those
/// concerns do not remain mixed with runtime and conversation state.
class CodexPluginManagementState {
  List<CodexPlugin> plugins = const [];
  bool pluginsLoading = false;
  bool pluginSaving = false;
  String? pluginsError;
  String? pluginActionError;
  String? pluginActionWarning;
  String? pluginActionProgress;
  String? pluginActionResult;
  String? pluginActionTargetId;
  bool pluginRuntimeRestartRequired = false;

  List<CodexMcpServer> mcpServers = const [];
  bool mcpServersLoading = false;
  String? mcpServersError;
  List<CodexMcpRuntimeStatus> runtimeMcpServerStatuses = const [];
  bool runtimeMcpServerStatusesLoading = false;
  String? runtimeMcpServerStatusesError;
  String? runtimeMcpServerStatusesThreadId;

  List<CodexSkill> skills = const [];
  bool skillsLoading = false;
  String? skillsLoadingWorkspace;
  String? skillsError;

  List<CodexMarketplace> marketplaces = const [];
  bool marketplacesLoading = false;
  String? marketplacesError;

  void clearWorkspaceMcp() {
    mcpServers = const [];
    mcpServersLoading = false;
    mcpServersError = null;
    runtimeMcpServerStatuses = const [];
    runtimeMcpServerStatusesLoading = false;
    runtimeMcpServerStatusesError = null;
    runtimeMcpServerStatusesThreadId = null;
  }
}
