/// Owns request markers for runtime configuration and capability catalog reads.
///
/// Configuration parsing, model capability derivation, and fallback behavior
/// remain in the controller. This state only rejects stale async responses.
class CodexConfigurationRefreshState {
  int configurationRequest = 0;
  int modelCatalogRequest = 0;
  int collaborationModesRequest = 0;

  int nextConfigurationRequest() => ++configurationRequest;

  int nextModelCatalogRequest() => ++modelCatalogRequest;

  int nextCollaborationModesRequest() => ++collaborationModesRequest;

  void invalidateConfiguration() => configurationRequest++;
}
