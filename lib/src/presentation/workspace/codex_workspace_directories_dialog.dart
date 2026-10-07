import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_controller_builder.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_directory_tile.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_muted_text.dart';

class CodexWorkspaceDirectoriesDialog extends StatelessWidget {
  const CodexWorkspaceDirectoriesDialog({
    super.key,
    this.overrideController,
    required this.onAddDirectory,
    required this.onCreateWorkspace,
  });

  final CodexController? overrideController;
  final Future<bool> Function() onAddDirectory;
  final Future<void> Function() onCreateWorkspace;

  @override
  Widget build(BuildContext context) {
    return ControllerBuilder(
      overrideController: overrideController,
      builder: (context, controller) {
        final primary = controller.workspacePath;
        final additional = controller.additionalWorkspacePaths;
        final workspaces = controller.workspaceConfigurations;
        return AlertDialog(
          key: const Key('workspace-directories-dialog'),
          title: const Text('工作区'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('每个工作区会独立保存主目录、附加目录和本地历史。新建项目只加入列表，切换后才会连接运行时。'),
                  if (!controller.canChangePrimaryWorkspace) ...[
                    const SizedBox(height: 8),
                    MutedText(
                      '${controller.changePrimaryWorkspaceDisabledReason ?? '当前暂时不能切换工作区。'}仍可新建项目或调整附加目录。',
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        '已保存工作区',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(width: 8),
                      Text('${workspaces.length}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (workspaces.isEmpty)
                    const WorkspaceDirectoryTile(
                      key: Key('saved-workspaces-empty'),
                      path: null,
                      label: '暂无工作区',
                      description: '点击“新建工作区”选择主目录',
                      primary: true,
                    )
                  else
                    ...workspaces.map((workspace) {
                      final active = workspace.primaryPath == primary;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: WorkspaceDirectoryTile(
                          key: ValueKey(
                            'workspace-profile-${workspace.primaryPath}',
                          ),
                          path: workspace.isUnrooted
                              ? null
                              : workspace.primaryPath,
                          label: active ? '当前工作区' : '工作区',
                          description: workspace.isUnrooted
                              ? '未添加源文件夹'
                              : workspace.additionalPaths.isEmpty
                              ? '仅主目录'
                              : '${workspace.additionalPaths.length} 个附加目录',
                          primary: active,
                          trailing: active
                              ? const Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text('当前'),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      key: ValueKey(
                                        'switch-workspace-${workspace.primaryPath}',
                                      ),
                                      onPressed:
                                          !workspace.isUnrooted &&
                                              controller
                                                  .canChangePrimaryWorkspace
                                          ? () => controller
                                                .selectWorkspaceAndReconnect(
                                                  workspace.primaryPath,
                                                )
                                          : null,
                                      child: const Text('切换'),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        'forget-workspace-${workspace.primaryPath}',
                                      ),
                                      tooltip: '从列表移除（不会删除目录或历史）',
                                      onPressed: () =>
                                          controller.forgetWorkspace(
                                            workspace.primaryPath,
                                          ),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    }),
                  const SizedBox(height: 20),
                  Text(
                    '当前工作区目录',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  WorkspaceDirectoryTile(
                    key: const Key('primary-workspace-directory'),
                    path: primary,
                    label: '主目录',
                    description: '配置、历史、Git 和默认工作位置',
                    primary: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '附加目录',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(width: 8),
                      Text('${additional.length}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (additional.isEmpty)
                    const WorkspaceDirectoryTile(
                      key: Key('additional-workspaces-empty'),
                      path: null,
                      label: '暂无附加目录',
                      description: '添加后，新任务可以同时访问这些目录',
                    )
                  else
                    ...additional.map(
                      (path) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: WorkspaceDirectoryTile(
                          key: ValueKey('additional-workspace-$path'),
                          path: path,
                          label: '附加目录',
                          description: '供后续新任务访问',
                          trailing: IconButton(
                            tooltip: '移除附加目录',
                            onPressed: () =>
                                controller.removeWorkspaceRoot(path),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
            OutlinedButton.icon(
              key: const Key('add-workspace-directory-button'),
              onPressed: primary == null ? null : () => onAddDirectory(),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('添加目录'),
            ),
            Tooltip(
              message: controller.canCreateWorkspace ? '新建工作区' : '正在保存项目，请稍候。',
              child: FilledButton.icon(
                key: const Key('create-workspace-button'),
                onPressed: controller.canCreateWorkspace
                    ? onCreateWorkspace
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('新建工作区'),
              ),
            ),
          ],
        );
      },
    );
  }
}
