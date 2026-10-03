import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_page_state.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';

/// Codex 风格的应用设置工作区。
/// Codex-style application settings workspace.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({
    required this.controller,
    required this.runtimeConfigurationStore,
    required this.navigationWidth,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.highContrast,
    required this.onHighContrastChanged,
    required this.onChooseWorkspace,
    required this.onShowCodexConfiguration,
    required this.onConfigureRuntime,
    required this.onAddMarketplace,
    required this.onManageMarketplaces,
    required this.onShowAccount,
    required this.onOpenConversation,
    super.key,
  });

  final CodexController controller;
  final RuntimeConfigurationStore runtimeConfigurationStore;

  /// Width shared with the main workspace sidebar, including user resizing.
  final double navigationWidth;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final bool highContrast;
  final ValueChanged<bool>? onHighContrastChanged;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onShowCodexConfiguration;
  final Future<void> Function() onConfigureRuntime;
  final Future<void> Function() onAddMarketplace;
  final Future<void> Function() onManageMarketplaces;
  final Future<void> Function() onShowAccount;
  final VoidCallback onOpenConversation;

  @override
  ConsumerState<SettingsPage> createState() => SettingsPageState();
}
