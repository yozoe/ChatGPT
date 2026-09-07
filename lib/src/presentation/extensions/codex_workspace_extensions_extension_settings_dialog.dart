// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_dialog_state.dart';

/// 提供插件、MCP 服务器和技能的统一扩展管理入口。
/// Provides a unified management entry point for plugins, MCP servers, and skills.
class ExtensionSettingsDialog extends StatefulWidget {
  const ExtensionSettingsDialog({
    super.key,
    required this.controller,
    required this.onAddMarketplace,
    required this.onManageMarketplaces,
    this.embedded = false,
  });

  final CodexController controller;
  final Future<void> Function() onAddMarketplace;
  final Future<void> Function() onManageMarketplaces;

  /// Renders the same management controls in a settings content pane instead
  /// of wrapping them in a dialog.
  final bool embedded;

  @override
  State<ExtensionSettingsDialog> createState() =>
      ExtensionSettingsDialogState();
}
