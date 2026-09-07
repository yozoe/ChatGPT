// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugins_page_state.dart';

class PluginsPage extends StatefulWidget {
  const PluginsPage({
    super.key,
    required this.controller,
    required this.onAddMarketplace,
    required this.onOpenSettings,
    required this.onCreatePlugin,
    required this.onRecordSkill,
  });

  final CodexController controller;
  final Future<void> Function() onAddMarketplace;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onCreatePlugin;
  final VoidCallback onRecordSkill;

  @override
  State<PluginsPage> createState() => PluginsPageState();
}
