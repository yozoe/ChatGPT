// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_workspace_tile_state.dart';

class SidebarWorkspaceTile extends StatefulWidget {
  const SidebarWorkspaceTile({
    required this.workspace,
    required this.active,
    required this.pinned,
    required this.onMore,
    required this.onEdit,
    required this.canCreateTask,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onHoverStart,
    required this.onHoverEnd,
    super.key,
  });

  final WorkspaceConfiguration workspace;
  final bool active;
  final bool pinned;
  final void Function(BuildContext context) onMore;
  final void Function(BuildContext context) onEdit;
  final bool canCreateTask;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final void Function(BuildContext context) onHoverStart;
  final VoidCallback onHoverEnd;

  @override
  State<SidebarWorkspaceTile> createState() => SidebarWorkspaceTileState();
}
