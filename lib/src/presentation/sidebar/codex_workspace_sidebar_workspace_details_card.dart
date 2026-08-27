// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_details_row.dart';

class WorkspaceDetailsCard extends StatelessWidget {
  const WorkspaceDetailsCard({
    required this.workspace,
    required this.pinned,
    required this.taskCount,
    required this.onTogglePin,
    required this.onEditProject,
  });

  final WorkspaceConfiguration workspace;
  final bool pinned;
  final int? taskCount;
  final VoidCallback onTogglePin;
  final void Function(String primaryPath) onEditProject;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final taskCountLabel = switch (taskCount) {
      null => '任务数加载中…',
      < 0 => '任务数不可用',
      final count => '$count 个任务',
    };
    final paths = [workspace.primaryPath, ...workspace.additionalPaths];
    return Material(
      color: palette.module,
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      workspace.name ??
                          workspaceDirectoryName(workspace.primaryPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: pinned ? '取消置顶项目' : '置顶项目',
                    onPressed: onTogglePin,
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 17,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            WorkspaceDetailsRow(
              icon: Icons.chat_bubble_outline,
              label: taskCountLabel,
            ),
            Divider(height: 1, color: palette.border),
            for (final path in paths)
              WorkspaceDetailsRow(
                icon: Icons.folder_outlined,
                label: _compactPath(path),
              ),
            Divider(height: 1, color: palette.border),
            InkWell(
              onTap: () => onEditProject(workspace.primaryPath),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 17),
                    SizedBox(width: 11),
                    Text(
                      '编辑项目',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _compactPath(String path) {
    final home = Platform.environment['HOME'];
    return home != null && path.startsWith(home)
        ? '~${path.substring(home.length)}'
        : path;
  }
}
