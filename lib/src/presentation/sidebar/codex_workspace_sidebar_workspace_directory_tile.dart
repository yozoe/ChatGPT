// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class WorkspaceDirectoryTile extends StatelessWidget {
  const WorkspaceDirectoryTile({
    required this.path,
    required this.label,
    required this.description,
    this.primary = false,
    this.trailing,
    super.key,
  });

  final String? path;
  final String label;
  final String description;
  final bool primary;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final visiblePath = path ?? label;
    return Material(
      color: palette.raised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
      child: ListTile(
        leading: Icon(
          primary ? Icons.folder_special_outlined : Icons.folder_outlined,
        ),
        title: Tooltip(
          message: path ?? '',
          child: Text(
            visiblePath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('$label · $description'),
        ),
        trailing: trailing,
      ),
    );
  }
}
