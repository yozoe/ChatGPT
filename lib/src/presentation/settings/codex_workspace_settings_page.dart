import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_page_state.dart';

/// Codex 风格的应用设置工作区。
/// Codex-style application settings workspace.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({
    required this.controller,
    required this.navigationWidth,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onChooseWorkspace,
    required this.onShowCodexConfiguration,
    required this.onConfigureRuntime,
    required this.onAddMarketplace,
    required this.onManageMarketplaces,
    required this.onShowAccount,
    required this.onShowBrowser,
    required this.onOpenConversation,
    super.key,
  });

  final CodexController controller;

  /// Width shared with the main workspace sidebar, including user resizing.
  final double navigationWidth;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onShowCodexConfiguration;
  final Future<void> Function() onConfigureRuntime;
  final Future<void> Function() onAddMarketplace;
  final Future<void> Function() onManageMarketplaces;
  final Future<void> Function() onShowAccount;
  final VoidCallback onShowBrowser;
  final VoidCallback onOpenConversation;

  @override
  ConsumerState<SettingsPage> createState() => SettingsPageState();
}
