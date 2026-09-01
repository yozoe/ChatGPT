// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_dialog_state.dart';

class ExtensionSettingsDialog extends StatefulWidget {
  const ExtensionSettingsDialog({
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
