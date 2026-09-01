// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_source_row.dart';

class WorkspaceSourcesCard extends StatelessWidget {
  const WorkspaceSourcesCard({
    required this.primary,
    required this.additional,
    required this.onRemovePrimary,
    required this.onRemoveAdditional,
    required this.onAdd,
  });

  final String? primary;
  final List<String> additional;
  final VoidCallback? onRemovePrimary;
  final Future<void> Function(String path) onRemoveAdditional;
  final Future<bool> Function()? onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final rowBorder = BorderSide(color: palette.border);
    return Container(
      key: const Key('workspace-source-folders'),
      decoration: BoxDecoration(
        color: palette.raised.withValues(alpha: 0.34),
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (primary case final path?)
              WorkspaceSourceRow(
                path: path,
                primary: true,
                onRemove: onRemovePrimary,
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                child: Row(
                  children: [
                    Icon(Icons.folder_off_outlined, size: 18),
                    SizedBox(width: 17),
                    Text('尚未添加源文件夹'),
                  ],
                ),
              ),
            for (final path in additional)
              WorkspaceSourceRow(
                path: path,
                onRemove: () => onRemoveAdditional(path),
              ),
            Container(
              decoration: BoxDecoration(border: Border(top: rowBorder)),
              child: InkWell(
                key: const Key('add-workspace-directory-button'),
                onTap: onAdd == null ? null : () => onAdd!(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 18,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                        color: palette.muted,
                      ),
                      const SizedBox(width: 17),
                      Text(
                        '添加文件夹',
                        style: TextStyle(
                          color: palette.trace,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
