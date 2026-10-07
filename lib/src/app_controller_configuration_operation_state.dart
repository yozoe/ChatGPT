/// Owns generations for runtime configuration capability probes and writes.
///
/// The controller still performs configuration reads, writes, error handling,
/// and user-facing notifications. This state only rejects stale async work and
/// keeps capability probing independent from queued setting writes.
class CodexConfigurationOperationState {
  int configWriterProbeEpoch = -1;
  int agentDefaultSettingsWriteGeneration = 0;

  void invalidateConfigWriterProbe() {
    configWriterProbeEpoch = -1;
  }

  bool isConfigWriterProbeCurrent(int runtimeEpoch) {
    return configWriterProbeEpoch == runtimeEpoch;
  }

  void markConfigWriterProbe(int runtimeEpoch) {
    configWriterProbeEpoch = runtimeEpoch;
  }

  int nextAgentDefaultSettingsWriteGeneration() {
    return ++agentDefaultSettingsWriteGeneration;
  }

  bool isAgentDefaultSettingsWriteCurrent(int generation) {
    return generation == agentDefaultSettingsWriteGeneration;
  }
}
