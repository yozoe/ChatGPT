import 'package:chatgpt/src/services/codex_app_server_support.dart';

import 'app_controller_codex_model_option.dart';
import 'app_controller_reasoning_effort.dart';

/// Owns model/configuration snapshots and serialized preference writes.
///
/// The controller still owns App Server requests, persistence side effects,
/// fallback decisions, and user notifications. This container only keeps the
/// mutable state that those operations update, so runtime invalidation cannot
/// accidentally leave a stale model catalog visible.
class CodexModelConfigurationState {
  Future<void> reasoningEffortSave = Future.value();
  Future<void> modelSelectionSave = Future.value();
  Future<void> approvalModeSave = Future.value();
  Future<void> agentDefaultSettingsWrite = Future.value();

  Map<String, Set<ReasoningEffort>> reasoningEffortsByModel = const {};
  String? catalogDefaultModelId;
  JsonMap? planCollaborationModePreset;
  JsonMap? defaultCollaborationModePreset;

  String? configuredModelId;
  String? configuredProviderId;
  String? configuredModelSource;
  String? configuredProviderSource;
  String? modelCatalogError;
  String? selectedModelId;
  List<CodexModelOption> modelOptions = const [];

  bool codexConfigurationLoading = false;
  bool codexConfigurationRead = false;
  String? codexConfigurationError;
  bool agentDefaultSettingsWriteSupported = false;
  String? agentDefaultSettingsWriteError;

  void clearRuntimeResolvedConfiguration() {
    configuredModelId = null;
    configuredProviderId = null;
    configuredModelSource = null;
    configuredProviderSource = null;
    codexConfigurationLoading = false;
    codexConfigurationRead = false;
    codexConfigurationError = null;
    agentDefaultSettingsWriteSupported = false;
    agentDefaultSettingsWriteError = null;
    reasoningEffortsByModel = const {};
    catalogDefaultModelId = null;
    planCollaborationModePreset = null;
    defaultCollaborationModePreset = null;
    modelOptions = const [];
    modelCatalogError = null;
  }
}
