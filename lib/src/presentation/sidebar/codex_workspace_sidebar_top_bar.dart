// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_editable_task_title.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    required this.controller,
    required this.themeMode,
    required this.themePreset,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
    required this.onChooseWorkspace,
    required this.onAccount,
    required this.onCodexConfiguration,
    required this.onPlugins,
    required this.showIdentity,
    required this.showControls,
    this.showTaskContext = false,
    this.onShowFileChanges,
    super.key,
  });

  final CodexController controller;
  final ThemeMode themeMode;
  final YeknomColorPreset themePreset;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<YeknomColorPreset>? onThemePresetChanged;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onAccount;
  final Future<void> Function() onCodexConfiguration;
  final Future<void> Function() onPlugins;
  final bool showIdentity;
  final bool showControls;
  final bool showTaskContext;
  final Future<void> Function()? onShowFileChanges;

  /// 构建归属左侧项目列或右侧工作台列的独立顶部栏。
  /// Builds an independent top bar for either the project or workbench column.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final color = switch (controller.status) {
      RuntimeStatus.ready => palette.ack,
      RuntimeStatus.running => palette.active,
      RuntimeStatus.failed => palette.fault,
      _ => palette.muted,
    };
    final label = switch (controller.status) {
      RuntimeStatus.stopped =>
        controller.workspacePath == null ? '等待目录' : '等待连接',
      RuntimeStatus.starting => '连接中',
      RuntimeStatus.ready => '已就绪',
      RuntimeStatus.running => '执行中',
      RuntimeStatus.failed => '连接失败',
    };
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1180;
            final showProvider = showTaskContext && constraints.maxWidth >= 740;
            final showSandbox = showTaskContext && constraints.maxWidth >= 880;
            return Row(
              children: [
                if (showIdentity) ...[
                  Icon(Icons.auto_awesome, color: palette.ack),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Codex Desk',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(label: label, color: color),
                ],
                if (showTaskContext) ...[
                  Flexible(child: EditableTaskTitle(controller: controller)),
                  if (showProvider) ...[
                    const SizedBox(width: 12),
                    ProviderChip(
                      label: '${controller.providerLabel} / App Server',
                    ),
                  ],
                  if (showSandbox) ...[
                    const SizedBox(width: 8),
                    const ProviderChip(label: 'workspace-write'),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('workbench-file-changes-button'),
                    tooltip: '查看文件变更',
                    onPressed: onShowFileChanges,
                    icon: const Icon(Icons.difference_outlined, size: 16),
                  ),
                ],
                if (showControls) ...[
                  PopupMenuButton<ThemeAction>(
                    tooltip:
                        '主题：${themeModeLabel(themeMode)} · ${themePresetLabel(themePreset)}',
                    enabled:
                        onThemeModeChanged != null ||
                        onThemePresetChanged != null,
                    icon: Icon(themeModeIcon(themeMode)),
                    onSelected: (action) {
                      switch (action) {
                        case ThemeAction.system:
                          onThemeModeChanged?.call(ThemeMode.system);
                        case ThemeAction.light:
                          onThemeModeChanged?.call(ThemeMode.light);
                        case ThemeAction.dark:
                          onThemeModeChanged?.call(ThemeMode.dark);
                        case ThemeAction.workbench:
                          onThemePresetChanged?.call(
                            YeknomColorPreset.workbench,
                          );
                        case ThemeAction.cobalt:
                          onThemePresetChanged?.call(YeknomColorPreset.cobalt);
                        case ThemeAction.orchid:
                          onThemePresetChanged?.call(YeknomColorPreset.orchid);
                        case ThemeAction.graphite:
                          onThemePresetChanged?.call(
                            YeknomColorPreset.graphite,
                          );
                        case ThemeAction.obsidian:
                          onThemePresetChanged?.call(
                            YeknomColorPreset.obsidian,
                          );
                        case ThemeAction.midnight:
                          onThemePresetChanged?.call(
                            YeknomColorPreset.midnight,
                          );
                        case ThemeAction.blackberry:
                          onThemePresetChanged?.call(
                            YeknomColorPreset.blackberry,
                          );
                        case ThemeAction.sage:
                          onThemePresetChanged?.call(YeknomColorPreset.sage);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<ThemeAction>(
                        enabled: false,
                        child: Text('显示模式'),
                      ),
                      CheckedPopupMenuItem(
                        key: const Key('theme-mode-system'),
                        value: ThemeAction.system,
                        checked: themeMode == ThemeMode.system,
                        child: const Text('跟随系统'),
                      ),
                      CheckedPopupMenuItem(
                        key: const Key('theme-mode-light'),
                        value: ThemeAction.light,
                        checked: themeMode == ThemeMode.light,
                        child: const Text('浅色'),
                      ),
                      CheckedPopupMenuItem(
                        key: const Key('theme-mode-dark'),
                        value: ThemeAction.dark,
                        checked: themeMode == ThemeMode.dark,
                        child: const Text('深色'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<ThemeAction>(
                        enabled: false,
                        child: Text('配色'),
                      ),
                      ...ThemeAction.values
                          .where((action) => action.preset != null)
                          .map(
                            (action) => CheckedPopupMenuItem(
                              key: ValueKey(
                                'theme-preset-${action.preset!.name}',
                              ),
                              value: action,
                              checked: action.preset == themePreset,
                              child: Text(themePresetLabel(action.preset!)),
                            ),
                          ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  if (compact)
                    IconButton(
                      tooltip: '账户：${controller.authLabel}',
                      onPressed: onAccount,
                      icon: const Icon(Icons.person_outline),
                    )
                  else
                    TextButton.icon(
                      onPressed: onAccount,
                      icon: const Icon(Icons.person_outline),
                      label: Text(controller.authLabel),
                    ),
                  const SizedBox(width: 8),
                  if (compact)
                    IconButton(
                      key: const Key('codex-configuration-button'),
                      tooltip: 'Provider：${controller.providerLabel}',
                      onPressed: onCodexConfiguration,
                      icon: const Icon(Icons.route_outlined),
                    )
                  else
                    TextButton.icon(
                      key: const Key('codex-configuration-button'),
                      onPressed: onCodexConfiguration,
                      icon: const Icon(Icons.route_outlined),
                      label: Text(controller.providerLabel),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('plugin-manager-button'),
                    tooltip: '插件管理',
                    onPressed: onPlugins,
                    icon: const Icon(Icons.extension_outlined),
                  ),
                  const SizedBox(width: 4),
                  if (compact)
                    IconButton(
                      tooltip: '管理工作区',
                      onPressed: onChooseWorkspace,
                      icon: const Icon(Icons.folder_copy_outlined),
                    )
                  else
                    TextButton.icon(
                      onPressed: onChooseWorkspace,
                      icon: const Icon(Icons.folder_copy_outlined),
                      label: const Text('工作区'),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
