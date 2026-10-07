import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_controller_builder.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_name_field.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_sources_card.dart';

class CodexWorkspaceEditDialog extends StatelessWidget {
  const CodexWorkspaceEditDialog({
    super.key,
    required this.primary,
    required this.nameController,
    this.overrideController,
    required this.onForgetInactiveWorkspace,
    required this.onAddDirectory,
  });

  final String primary;
  final TextEditingController nameController;
  final CodexController? overrideController;
  final Future<bool> Function(String primaryPath) onForgetInactiveWorkspace;
  final Future<bool> Function(String primaryPath) onAddDirectory;

  @override
  Widget build(BuildContext context) {
    return ControllerBuilder(
      overrideController: overrideController,
      builder: (context, controller) {
        final currentConfiguration = controller.workspaceConfigurations
            .firstWhere(
              (candidate) => candidate.primaryPath == primary,
              orElse: () => WorkspaceConfiguration(primaryPath: primary),
            );
        final additional = currentConfiguration.additionalPaths;
        final palette = YeknomPalette.of(context);
        return KeyedSubtree(
          key: const Key('workspace-directories-dialog'),
          child: Dialog(
            key: const Key('workspace-edit-dialog'),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: palette.module,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 34, 40, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '编辑项目',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                ),
                          ),
                        ),
                        IconButton(
                          key: const Key('close-workspace-edit-dialog'),
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 25),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    WorkspaceNameField(controller: nameController),
                    const SizedBox(height: 28),
                    Text(
                      '源文件夹',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: WorkspaceSourcesCard(
                        primary: currentConfiguration.isUnrooted
                            ? null
                            : primary,
                        additional: additional,
                        onRemovePrimary: controller.canChangePrimaryWorkspace
                            ? () async {
                                final removed =
                                    primary == controller.workspacePath
                                    ? await controller.removeCurrentWorkspace()
                                    : await onForgetInactiveWorkspace(primary);
                                if (removed && context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              }
                            : null,
                        onRemoveAdditional: (path) => controller
                            .removeWorkspaceRootFromWorkspace(primary, path),
                        onAdd: () => onAddDirectory(primary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        TextButton(
                          key: const Key('remove-local-workspace-button'),
                          onPressed: controller.canChangePrimaryWorkspace
                              ? () async {
                                  final removed =
                                      primary == controller.workspacePath
                                      ? await controller
                                            .removeCurrentWorkspace()
                                      : await onForgetInactiveWorkspace(
                                          primary,
                                        );
                                  if (removed && context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                }
                              : null,
                          style: TextButton.styleFrom(
                            foregroundColor: palette.fault,
                            backgroundColor: palette.fault.withValues(
                              alpha: 0.14,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            '移除本地项目',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const Spacer(),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            TextButton(
                              key: const Key('cancel-workspace-edit'),
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: palette.muted,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 15,
                                ),
                              ),
                              child: const Text(
                                '取消',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Positioned.fill(
                              child: Opacity(
                                opacity: 0,
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('关闭'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        FilledButton(
                          key: const Key('save-workspace-edit'),
                          onPressed: () async {
                            await controller.renameWorkspace(
                              primary,
                              nameController.text,
                            );
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.black,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 30,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            '保存',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
