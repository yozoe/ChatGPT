// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';

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
    return Container(
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
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
