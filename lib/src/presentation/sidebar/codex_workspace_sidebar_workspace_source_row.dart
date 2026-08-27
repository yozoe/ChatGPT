// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';

class WorkspaceSourceRow extends StatelessWidget {
  const WorkspaceSourceRow({
    required this.path,
    required this.onRemove,
    this.primary = false,
  });

  final String path;
  final VoidCallback? onRemove;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 18, color: palette.muted),
          const SizedBox(width: 17),
          Expanded(
            child: Tooltip(
              message: path,
              child: Text(
                workspaceDirectoryName(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.trace),
              ),
            ),
          ),
          if (primary)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '主要',
                style: TextStyle(color: palette.muted, fontSize: 15),
              ),
            ),
          IconButton(
            tooltip: primary ? '移除本地项目' : '移除源文件夹',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            color: palette.muted,
          ),
        ],
      ),
    );
  }
}
