/// Owns browser-tool invocation markers that are scoped to one runtime session.
///
/// The controller still performs URL validation, approval, navigation, and
/// persistence. This state only groups de-duplication, queued navigation, and
/// the non-persisted "allow all sites" session grant.
class CodexBrowserInvocationState {
  final Set<String> handledInvocationIds = <String>{};
  final List<String> queuedInvocations = <String>[];
  bool allowAllSites = false;

  void clear() {
    handledInvocationIds.clear();
    queuedInvocations.clear();
    allowAllSites = false;
  }
}
