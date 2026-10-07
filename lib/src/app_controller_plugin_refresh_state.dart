/// Owns request markers used to reject stale plugin, Skill, and MCP refreshes.
///
/// The controller still owns loading flags, errors, workspace/thread scoping,
/// and the catalog data itself. This state only centralizes the monotonically
/// increasing markers and the invalidation groups used by those refreshes.
class CodexPluginRefreshState {
  int pluginsRequest = 0;
  int marketplacesRequest = 0;
  int mcpServersRequest = 0;
  int runtimeMcpStatusesRequest = 0;
  int skillsRequest = 0;

  int nextPluginsRequest() => ++pluginsRequest;

  int nextMarketplacesRequest() => ++marketplacesRequest;

  int nextMcpServersRequest() => ++mcpServersRequest;

  int nextRuntimeMcpStatusesRequest() => ++runtimeMcpStatusesRequest;

  int nextSkillsRequest() => ++skillsRequest;

  /// Invalidates catalog reads that may be superseded by a plugin mutation.
  void invalidatePluginCatalog() {
    pluginsRequest++;
    marketplacesRequest++;
  }

  /// Invalidates workspace-scoped MCP reads during a project switch.
  void invalidateMcpWorkspace() {
    mcpServersRequest++;
    runtimeMcpStatusesRequest++;
  }
}
