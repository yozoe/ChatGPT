import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_page_state.dart';

/// Codex 风格的应用设置工作区。
/// Codex-style application settings workspace.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onChooseWorkspace,
    required this.onConfigureRuntime,
    required this.onShowPlugins,
    required this.onShowAccount,
    required this.onOpenConversation,
    super.key,
  });

  final CodexController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onConfigureRuntime;
  final Future<void> Function() onShowPlugins;
  final Future<void> Function() onShowAccount;
  final VoidCallback onOpenConversation;

  @override
  State<SettingsPage> createState() => SettingsPageState();
}
