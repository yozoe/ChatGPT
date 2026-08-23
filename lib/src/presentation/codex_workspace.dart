import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

import '../app_controller.dart';
import '../domain/codex_file_change.dart';
import '../domain/git_project_status.dart';
import '../domain/codex_plugin.dart';
import '../domain/codex_skill.dart';
import '../domain/codex_marketplace.dart';
import '../domain/codex_thread.dart';
import '../domain/pending_approval.dart';
import '../domain/task_plan.dart';
import '../domain/timeline_entry.dart';
import '../domain/workspace_configuration.dart';
import '../services/clipboard_file_reader.dart';

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return const [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  ].any(lower.endsWith);
}

/// Identifies a retained timeline viewport within its owning workspace.
/// 在所属项目范围内标识保留的时间线视口。
class _ThreadViewportKey {
  const _ThreadViewportKey({required this.workspace, required this.threadId});

  final String? workspace;
  final String? threadId;

  String get storageKey =>
      '${workspace ?? 'no-workspace'}:${threadId ?? 'draft'}';

  @override
  bool operator ==(Object other) =>
      other is _ThreadViewportKey &&
      workspace == other.workspace &&
      threadId == other.threadId;

  @override
  int get hashCode => Object.hash(workspace, threadId);
}

class CodexWorkspace extends ConsumerStatefulWidget {
  const CodexWorkspace({
    this.controller,
    this.themeMode = ThemeMode.dark,
    this.themePreset = YeknomColorPreset.midnight,
    this.onThemeModeChanged,
    this.onThemePresetChanged,
    super.key,
  });

  /// 测试或嵌入式场景可显式注入控制器；正常运行时从 Riverpod 读取共享实例。
  /// Tests and embedded callers may inject a controller; normal execution reads the shared Riverpod instance.
  final CodexController? controller;
  final ThemeMode themeMode;
  final YeknomColorPreset themePreset;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<YeknomColorPreset>? onThemePresetChanged;

  /// 创建承载工作区页面状态的 State 对象。
  /// Creates the State object that owns workspace-page state.
  @override
  ConsumerState<CodexWorkspace> createState() => _CodexWorkspaceState();
}

class _CodexWorkspaceState extends ConsumerState<CodexWorkspace> {
  final TextEditingController _composer = TextEditingController();
  final Map<_ThreadViewportKey, ScrollController> _timelineScrollControllers =
      {};
  final Map<_ThreadViewportKey, _TimelinePageData> _timelinePages = {};
  final Map<_ThreadViewportKey, bool> _fileChangeSummaryExpanded = {};
  final Map<String, bool> _activityListExpanded = {};
  late ScrollController _timelineScrollController;
  late _ThreadViewportKey _displayedThreadKey;
  bool _timelineScrollScheduled = false;
  bool _threadHistoryLoading = false;
  bool _suppressTimelineScrollAfterThreadResume = false;
  int _timelineScrollGeneration = 0;
  static const _minimumSidebarWidth = 210.0;
  static const _maximumSidebarWidth = 420.0;
  static const _minimumInspectorWidth = 280.0;
  static const _maximumInspectorWidth = 460.0;
  double _sidebarWidth = 250;
  double _inspectorWidth = 352;
  late final CodexController _controller;

  /// 注册控制器监听器，使时间线在内容更新后自动滚动。
  /// Registers the controller listener that scrolls the timeline after updates.
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ref.read(codexControllerProvider)!;
    _displayedThreadKey = _viewportKey(_controller.activeThreadId);
    _timelineScrollController = _timelineScrollControllers.putIfAbsent(
      _displayedThreadKey,
      ScrollController.new,
    );
    _captureActiveTimelinePage();
    _controller.addListener(_handleControllerUpdate);
  }

  /// 移除监听器并释放编辑、滚动与控制器资源。
  /// Removes listeners and releases composer, scrolling, and controller resources.
  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
    _composer.dispose();
    for (final controller in _timelineScrollControllers.values.toSet()) {
      controller.dispose();
    }
    // 显式注入的控制器沿用原有由工作区释放的约定；Provider 创建的
    // 控制器由 ProviderScope 统一释放。
    // Explicitly injected controllers retain the original workspace ownership;
    // Provider-created controllers are disposed by ProviderScope.
    if (widget.controller != null) _controller.dispose();
    super.dispose();
  }

  /// 响应控制器更新；显式注入时由工作区重建，Provider 场景仍由 ref.watch 重建。
  /// Responds to controller updates; the workspace rebuilds explicit injections while ref.watch rebuilds provider state.
  void _handleControllerUpdate() {
    if (_controller.isResumingThread) {
      _timelineScrollGeneration++;
      _timelineScrollScheduled = false;
      _suppressTimelineScrollAfterThreadResume = true;
      // Cancel an animation that may still be finishing from the previous
      // task before the newly restored timeline is laid out.
      if (_timelineScrollController.hasClients) {
        final position = _timelineScrollController.position;
        if (position.hasPixels) position.jumpTo(position.pixels);
      }
      _activateTimelineViewport(_controller.activeThreadId);
      if (!_controller.hasCachedActiveThreadView) {
        _threadHistoryLoading = true;
        _captureActiveTimelinePage();
      } else {
        _threadHistoryLoading = false;
        // The controller can outlive this workspace State (for example after
        // the shell is rebuilt). Recreate the rendering inputs only when the
        // retained UI page is absent, so IndexedStack never falls back to an
        // unrelated task while preserving existing mounted pages unchanged.
        // 控制器可能比当前工作区 State 存活更久（例如外壳重建后）。仅在
        // 保活 UI 页面缺失时重建渲染输入，避免 IndexedStack 回退到无关任务，
        // 已挂载页面则保持不变。
        if (!_timelinePages.containsKey(_displayedThreadKey)) {
          _captureActiveTimelinePage();
        }
      }
      if (widget.controller != null && mounted) setState(() {});
      return;
    }
    _activateTimelineViewport(_controller.activeThreadId);
    _pruneTimelineViewports();
    _captureActiveTimelinePage();
    if (widget.controller != null && mounted) setState(() {});
    if (_threadHistoryLoading) {
      _finishFirstThreadViewport();
      return;
    }
    if (_suppressTimelineScrollAfterThreadResume) {
      _suppressTimelineScrollAfterThreadResume = false;
      return;
    }
    _scheduleTimelineScroll();
  }

  /// Switches to a task-specific viewport, preserving every visited task's
  /// exact scroll position rather than reusing one shared list controller.
  /// 切换到任务专属视口，保留每个已访问任务的精确滚动位置。
  void _activateTimelineViewport(String? threadId) {
    final key = _viewportKey(threadId);
    if (_displayedThreadKey == key) return;
    _displayedThreadKey = key;
    _timelineScrollController = _timelineScrollControllers.putIfAbsent(
      key,
      ScrollController.new,
    );
  }

  /// Captures the active task's rendered timeline inputs so previously opened
  /// tasks can remain mounted as complete pages instead of rebuilding from a
  /// shared timeline when the sidebar selection changes.
  /// 保存当前任务的时间线渲染输入，使已打开任务以完整页面保活，而不是在
  /// 侧栏切换时从共享时间线重新构建。
  void _captureActiveTimelinePage() {
    _timelinePages[_displayedThreadKey] = _TimelinePageData(
      entries: List.unmodifiable(_controller.entries),
      fileChanges: List.unmodifiable(_controller.fileChanges),
      turnDiff: _controller.turnDiff,
      showFileChangeSummary:
          _controller.status != RuntimeStatus.running &&
          _controller.fileChanges.isNotEmpty,
      canSteer: _controller.canSteer,
    );
  }

  _ThreadViewportKey _viewportKey(String? threadId) => _ThreadViewportKey(
    workspace: _controller.workspacePath,
    threadId: threadId,
  );

  /// Releases viewports whose controller-side page caches were removed by a
  /// project switch, history import, archive, or deletion.
  /// 释放已因项目切换、导入、归档或删除而失效的任务视口。
  void _pruneTimelineViewports() {
    final workspace = _controller.workspacePath;
    final activeThreadId = _controller.activeThreadId;
    final cachedThreadIds = _controller.cachedThreadViewIds;
    final staleKeys = _timelineScrollControllers.keys
        .where(
          (key) =>
              key.workspace != workspace ||
              (key.threadId != null &&
                  key.threadId != activeThreadId &&
                  !cachedThreadIds.contains(key.threadId)),
        )
        .toList(growable: false);
    for (final key in staleKeys) {
      final controller = _timelineScrollControllers.remove(key);
      _timelinePages.remove(key);
      _fileChangeSummaryExpanded.remove(key);
      _activityListExpanded.removeWhere(
        (activityKey, _) => activityKey.startsWith('${key.storageKey}/'),
      );
      if (controller == null) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) controller.dispose();
      });
    }
  }

  /// 在下一帧无动画定位时间线到最新内容。
  /// Positions the timeline at the latest content without animation next frame.
  void _scheduleTimelineScroll() {
    if (!mounted || _timelineScrollScheduled) return;
    _timelineScrollScheduled = true;
    final generation = _timelineScrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineScrollScheduled = false;
      if (!mounted ||
          generation != _timelineScrollGeneration ||
          !_timelineScrollController.hasClients) {
        return;
      }
      final position = _timelineScrollController.position;
      position.jumpTo(position.maxScrollExtent);
    });
  }

  /// Positions a first-time task history while the loading surface is still
  /// visible, then reveals the fully laid-out page without visible scrolling.
  /// 首次任务历史仍被加载画面覆盖时完成定位，随后直接显示完整页面。
  void _finishFirstThreadViewport() {
    if (!mounted) return;
    final threadId = _controller.activeThreadId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || threadId != _controller.activeThreadId) return;
      if (_timelineScrollController.hasClients) {
        final position = _timelineScrollController.position;
        position.jumpTo(position.maxScrollExtent);
      }
      if (mounted) {
        setState(() {
          _threadHistoryLoading = false;
          _suppressTimelineScrollAfterThreadResume = false;
        });
      }
    });
  }

  /// 打开创建项目弹窗，并在选择源文件夹后注册新的可切换工作区。
  /// Opens the create-project dialog and registers a new switchable workspace after its source folder is chosen.
  Future<void> _createWorkspace() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => _CreateWorkspaceDialog(
        onCreate: (path, name) async {
          final created = await _controller.createWorkspace(path);
          if (!created) return false;
          final primary = _controller.workspacePath;
          if (primary != null) {
            await _controller.renameWorkspace(primary, name);
          }
          return true;
        },
      ),
    );
  }

  /// 选择并添加一个附加工作区目录。
  /// Selects and adds an additional workspace directory.
  Future<bool> _addWorkspaceDirectory() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '添加目录');
      if (path != null && path.trim().isNotEmpty) {
        await _controller.addWorkspaceRoot(path);
        return true;
      }
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
    }
    return false;
  }

  /// 选择并添加目录到指定工作区，支持编辑非当前项目。
  /// Selects and adds a directory to a specified workspace, including inactive projects.
  Future<bool> _addWorkspaceDirectoryFor(String primaryPath) async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '添加文件夹');
      if (path == null || path.trim().isEmpty) return false;
      await _controller.addWorkspaceRootToWorkspace(primaryPath, path);
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
      return false;
    }
  }

  Future<bool> _forgetInactiveWorkspace(String primaryPath) async {
    final before = _controller.workspaceConfigurations.length;
    await _controller.forgetWorkspace(primaryPath);
    return _controller.workspaceConfigurations.length < before;
  }

  /// 展示可切换工作区列表，以及当前工作区的主目录与附加目录。
  /// Shows switchable workspaces plus the current workspace's primary and additional directories.
  Future<void> _showWorkspaceDirectories() async {
    await showDialog<void>(
      context: context,
      // 运行时切换与目录保存都可能在弹窗打开期间完成，按钮状态必须随控制器实时更新。
      // Runtime transitions and directory saves may finish while open, so actions must rebuild live.
      builder: (dialogContext) => _ControllerBuilder(
        overrideController: widget.controller,
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
                    const Text('每个工作区会独立保存主目录、附加目录和本地历史。新建或切换后会自动连接运行时。'),
                    if (!controller.canChangePrimaryWorkspace) ...[
                      const SizedBox(height: 8),
                      const _MutedText('当前任务执行完成后可以新建或切换工作区；附加目录仍可直接调整。'),
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
                      const _WorkspaceDirectoryTile(
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
                          child: _WorkspaceDirectoryTile(
                            key: ValueKey(
                              'workspace-profile-${workspace.primaryPath}',
                            ),
                            path: workspace.primaryPath,
                            label: active ? '当前工作区' : '工作区',
                            description: workspace.additionalPaths.isEmpty
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
                                            controller.canChangePrimaryWorkspace
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
                    _WorkspaceDirectoryTile(
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
                      const _WorkspaceDirectoryTile(
                        key: Key('additional-workspaces-empty'),
                        path: null,
                        label: '暂无附加目录',
                        description: '添加后，新任务可以同时访问这些目录',
                      )
                    else
                      ...additional.map(
                        (path) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _WorkspaceDirectoryTile(
                            key: ValueKey('additional-workspace-$path'),
                            path: path,
                            label: '附加目录',
                            description: '供后续新任务访问',
                            trailing: IconButton(
                              tooltip: '移除附加目录',
                              onPressed: () async {
                                await controller.removeWorkspaceRoot(path);
                              },
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
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
              OutlinedButton.icon(
                key: const Key('add-workspace-directory-button'),
                onPressed: primary != null
                    ? () async {
                        await _addWorkspaceDirectory();
                      }
                    : null,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('添加目录'),
              ),
              FilledButton.icon(
                key: const Key('create-workspace-button'),
                onPressed: controller.canChangePrimaryWorkspace
                    ? _createWorkspace
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('新建工作区'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 打开与 Codex 桌面端一致的项目编辑器，管理项目名称和源文件夹。
  /// Opens a Codex desktop-style project editor for the project label and source folders.
  Future<void> _showEditWorkspaceDialog([String? requestedPrimary]) async {
    final primary = requestedPrimary ?? _controller.workspacePath;
    if (primary == null) return;
    final configuration = _controller.workspaceConfigurations.firstWhere(
      (candidate) => candidate.primaryPath == primary,
      orElse: () => WorkspaceConfiguration(primaryPath: primary),
    );
    final nameController = TextEditingController(
      text: configuration.name ?? _workspaceDirectoryName(primary),
    );
    try {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (dialogContext) => _ControllerBuilder(
          overrideController: widget.controller,
          builder: (context, controller) {
            final currentPrimary = primary;
            final additional = controller.workspaceConfigurations
                .firstWhere(
                  (candidate) => candidate.primaryPath == currentPrimary,
                  orElse: () =>
                      WorkspaceConfiguration(primaryPath: currentPrimary),
                )
                .additionalPaths;
            final palette = YeknomPalette.of(context);
            return KeyedSubtree(
              // 保留旧的管理入口 key，便于嵌入方平滑迁移到新的编辑器。
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
                  constraints: const BoxConstraints(
                    maxWidth: 960,
                    maxHeight: 680,
                  ),
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
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close, size: 25),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        _WorkspaceNameField(controller: nameController),
                        const SizedBox(height: 28),
                        Text(
                          '源文件夹',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _WorkspaceSourcesCard(
                            primary: currentPrimary,
                            additional: additional,
                            onRemovePrimary:
                                controller.canChangePrimaryWorkspace
                                ? () async {
                                    final removed =
                                        currentPrimary ==
                                            controller.workspacePath
                                        ? await controller
                                              .removeCurrentWorkspace()
                                        : await _forgetInactiveWorkspace(
                                            currentPrimary,
                                          );
                                    if (removed && dialogContext.mounted) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                  }
                                : null,
                            onRemoveAdditional: (path) =>
                                controller.removeWorkspaceRootFromWorkspace(
                                  currentPrimary,
                                  path,
                                ),
                            onAdd: () =>
                                _addWorkspaceDirectoryFor(currentPrimary),
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
                                          currentPrimary ==
                                              controller.workspacePath
                                          ? await controller
                                                .removeCurrentWorkspace()
                                          : await _forgetInactiveWorkspace(
                                              currentPrimary,
                                            );
                                      if (removed && dialogContext.mounted) {
                                        Navigator.of(dialogContext).pop();
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
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: palette.muted,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 15,
                                    ),
                                  ),
                                  child: const Text(
                                    '取消',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                // 兼容旧版调用方仍查找“关闭”文本；视觉上完全隐藏。
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: 0,
                                    child: TextButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(),
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
                                  currentPrimary,
                                  nameController.text,
                                );
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
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
        ),
      );
    } finally {
      nameController.dispose();
    }
  }

  /// 读取输入框内容、清空编辑器并发送非空任务。
  /// Reads composer content, clears the editor, and sends a nonempty task.
  Future<bool> _send(_ComposerSubmission submission) async {
    final rawPrompt = _composer.text.trim();
    if (rawPrompt.isEmpty && !submission.hasContext) return false;
    final contextLines = <String>[];
    final additionalInput = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final skillNames = <String>{};
    final selectedSkills = [...submission.skills];
    if (submission.recordSkill) {
      final creator = _controller.skills
          .where((skill) => skill.name == 'skill-creator')
          .firstOrNull;
      if (creator != null) selectedSkills.add(creator);
      contextLines.add('请把本次任务的有效流程整理成一个可复用的 Codex 技能。');
    }
    for (final skill in selectedSkills) {
      if (!skillNames.add(skill.name)) continue;
      additionalInput.add({
        'type': 'skill',
        'name': skill.name,
        'path': skill.path,
      });
    }
    for (final attachment in submission.attachments) {
      final path = attachment.path;
      if (!attachment.isDirectory && _isImagePath(path)) {
        imagePaths.add(path);
        additionalInput.add({'type': 'localImage', 'path': path});
      } else {
        contextLines.add('附加路径：$path');
      }
    }
    if (submission.includeWorkspace && _controller.workspacePath != null) {
      contextLines.add('显式附加当前项目：${_controller.workspacePath}');
    }
    final skillPrefix = skillNames.map((name) => '\$$name').join(' ');
    final promptParts = <String>[
      if (skillPrefix.isNotEmpty) skillPrefix,
      rawPrompt.isEmpty ? '请分析已附加的内容。' : rawPrompt,
      if (contextLines.isNotEmpty) '\n${contextLines.join('\n')}',
    ];
    final sent = await _controller.sendPrompt(
      promptParts.join(' ').trim(),
      additionalInput: additionalInput,
      goal: submission.goal,
      planMode: submission.planMode,
      imagePaths: imagePaths,
    );
    if (sent) _composer.clear();
    return sent;
  }

  /// Sends composer text and context while a turn is running as a direction adjustment.
  /// 运行中 Composer 的文本与附件上下文通过 `turn/steer` 发送到当前活动 turn。
  Future<bool> _steer(_ComposerSubmission submission) async {
    final rawPrompt = _composer.text.trim();
    final contextLines = <String>[];
    final additionalInput = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final selectedSkills = [...submission.skills];
    final skillNames = <String>{};
    if (submission.recordSkill) {
      final creator = _controller.skills
          .where((skill) => skill.name == 'skill-creator')
          .firstOrNull;
      if (creator != null) selectedSkills.add(creator);
      contextLines.add('请把本次调整的有效流程整理成一个可复用的 Codex 技能。');
    }
    for (final skill in selectedSkills) {
      if (!skillNames.add(skill.name)) continue;
      additionalInput.add({
        'type': 'skill',
        'name': skill.name,
        'path': skill.path,
      });
    }
    for (final attachment in submission.attachments) {
      if (!attachment.isDirectory && _isImagePath(attachment.path)) {
        imagePaths.add(attachment.path);
        additionalInput.add({'type': 'localImage', 'path': attachment.path});
      } else {
        contextLines.add('附加路径：${attachment.path}');
      }
    }
    if (submission.includeWorkspace && _controller.workspacePath != null) {
      contextLines.add('显式附加当前项目：${_controller.workspacePath}');
    }
    if (submission.goal?.trim() case final goal? when goal.isNotEmpty) {
      contextLines.add('调整目标：$goal');
    }
    if (submission.planMode) {
      contextLines.add('请先给出执行计划，再继续处理这次调整。');
    }
    final skillPrefix = skillNames.map((name) => '\$$name').join(' ');
    final prompt = <String>[
      if (skillPrefix.isNotEmpty) skillPrefix,
      rawPrompt.isEmpty ? '请根据附加内容调整当前任务。' : rawPrompt,
      if (contextLines.isNotEmpty) '\n${contextLines.join('\n')}',
    ].join(' ').trim();
    return _controller.steerCurrentTurn(
      prompt,
      additionalInput: additionalInput,
      imagePaths: imagePaths,
    );
  }

  /// Opens a focused editor for steering the currently running turn.
  /// 打开“调整方向”编辑器，将新的指示发送到当前活动 turn。
  Future<void> _adjustDirection(String originalPrompt) async {
    var draft = '';
    final direction = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('adjust-direction-dialog'),
        title: const Text('调整方向'),
        content: SizedBox(
          width: 520,
          child: TextFormField(
            key: const Key('adjust-direction-field'),
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            onChanged: (value) => draft = value,
            decoration: InputDecoration(
              hintText: '告诉 Codex 接下来应该怎么调整…',
              helperText: '原指令：${originalPrompt.trim()}',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('send-adjust-direction'),
            onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
            child: const Text('发送调整'),
          ),
        ],
      ),
    );
    if (direction == null || direction.trim().isEmpty || !mounted) return;
    await _controller.steerCurrentTurn(direction);
  }

  /// 将当前项目的本地历史导出到用户选择的 JSON 文件；文件不包含 API Key。
  /// Exports the current workspace's local history to a user-selected JSON file without API keys.
  Future<void> _exportConversationHistory() async {
    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Codex Desk 历史', extensions: ['json']),
        ],
        suggestedName: 'codex-desk-history.json',
        confirmButtonText: '导出历史',
      );
      if (location == null) return;
      final content = _controller.exportConversationHistory();
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
        name: 'codex-desk-history.json',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本地历史已导出。文件可能包含对话和 Diff，请妥善保管。')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出历史失败：$error')));
      }
    }
  }

  /// 选择并确认导入历史 JSON 到当前项目的本地缓存。
  /// Selects and confirms importing history JSON into the current workspace cache.
  Future<void> _importConversationHistory() async {
    try {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Codex Desk 历史', extensions: ['json']),
        ],
        confirmButtonText: '导入历史',
      );
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入本地历史？'),
          content: const Text(
            '导入会替换当前项目在 Codex Desk 中缓存的任务列表、置顶状态、对话和 Diff。不会恢复 App Server 原始任务，也不会修改项目文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _controller.importConversationHistory(
        await selected.readAsString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本地历史已导入到当前项目。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入历史失败：$error')));
      }
    }
  }

  /// 显示账户状态以及 ChatGPT 和 API Key 登录入口。
  /// Shows account status plus ChatGPT and API-key login entry points.
  Future<void> _showAccount() async {
    final apiKey = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          return AlertDialog(
            title: const Text('账户与登录'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前状态：${controller.authLabel}'),
                  if (controller.accountEmail case final email?) ...[
                    const SizedBox(height: 4),
                    Text(email),
                  ],
                  const SizedBox(height: 16),
                  if (!controller.canStopRuntime)
                    const Text('请选择主目录；应用会自动连接本地运行时。')
                  else ...[
                    FilledButton.icon(
                      onPressed: controller.loginInProgress
                          ? null
                          : controller.startChatgptLogin,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('使用 ChatGPT 登录'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiKey,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'OpenAI API Key',
                        hintText: 'sk-…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) async {
                        await controller.loginWithApiKey(value);
                        apiKey.clear();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '密钥不会被此应用写入项目或日志；它会交给本地 Codex 运行时处理。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: controller.loginInProgress
                          ? null
                          : () async {
                              await controller.loginWithApiKey(apiKey.text);
                              apiKey.clear();
                            },
                      child: const Text('使用 API Key 登录'),
                    ),
                    if (controller.loginUrl case final authUrl?) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        authUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          final opened = await launchUrl(
                            Uri.parse(authUrl),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('无法打开浏览器。')),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('在浏览器中打开登录页'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
    apiKey.dispose();
  }

  /// 展示由 Codex App Server 原生加载的配置来源，不在应用内收集 Provider 凭据。
  /// Shows the configuration source loaded natively by App Server without collecting provider credentials.
  Future<void> _showCodexConfiguration() async {
    await _controller.refreshCodexConfiguration();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) => AlertDialog(
          key: const Key('codex-configuration-dialog'),
          title: const Text('Codex 配置'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '模型、Provider、Base URL 和凭据由本地 Codex App Server 按配置优先级直接读取，本应用不再单独收集或保存这些字段。',
                  ),
                  const SizedBox(height: 16),
                  Text('读取状态', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                    controller.codexConfigurationStatusLabel,
                    key: const Key('codex-configuration-status'),
                  ),
                  if (controller.codexConfigurationError case final error?) ...[
                    const SizedBox(height: 4),
                    Text(
                      error,
                      key: const Key('codex-configuration-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text('当前模型', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  SelectableText(
                    controller.configuredModelLabel,
                    key: const Key('codex-configured-model'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '来源：${controller.configuredModelSourceLabel}',
                    key: const Key('codex-configured-model-source'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Provider',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    controller.providerLabel,
                    key: const Key('codex-configured-provider'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '来源：${controller.configuredProviderSourceLabel}',
                    key: const Key('codex-configured-provider-source'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '用户配置文件',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    controller.codexUserConfigPath,
                    key: const Key('codex-configuration-path'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '“已读取”表示模型和 Provider 已由 Codex 运行时解析；凭据、网络和 Base URL 是否可用，仍需成功创建一次任务才能确认。',
                    key: const Key('codex-configuration-verification-note'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '输入框右下角的模型和推理强度选择只影响后续新建任务，不会改写 Codex 配置，也不会覆盖历史任务原有模型。',
                    key: const Key('codex-model-selection-scope-note'),
                    style: Theme.of(context).textTheme.bodySmall,
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
          ],
        ),
      ),
    );
  }

  /// 探测并显示 Codex CLI 状态，同时提供路径配置入口。
  /// Probes and shows Codex CLI status while offering path configuration.
  Future<void> _showRuntime() async {
    await _controller.inspectRuntime();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          final probe = controller.runtimeProbe;
          return AlertDialog(
            title: const Text('Codex CLI 运行时'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (controller.runtimeChecking)
                      const LinearProgressIndicator()
                    else if (probe?.isAvailable == true) ...[
                      const Text('已检测到可用的 Codex CLI。'),
                      const SizedBox(height: 8),
                      SelectableText(probe!.executablePath ?? ''),
                      if (probe.version?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          probe.version!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ] else ...[
                      Text(controller.runtimeError ?? '尚未检测到 Codex CLI。'),
                      const SizedBox(height: 12),
                      const Text('可在终端执行以下官方安装命令：'),
                      const SizedBox(height: 6),
                      const SelectableText(
                        'curl -fsSL https://chatgpt.com/codex/install.sh | sh',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '选择的路径仅保存为本应用设置；启动时会再次验证，不依赖 Finder 的 PATH。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '最近运行时日志（${controller.runtimeLogs.length}/200）',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: controller.runtimeLogs.isEmpty
                              ? null
                              : controller.clearRuntimeLogs,
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      key: const Key('runtime-diagnostics-log'),
                      constraints: const BoxConstraints(maxHeight: 180),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          controller.runtimeLogs.isEmpty
                              ? '本次应用运行中尚未记录 stderr 或协议日志。'
                              : controller.runtimeLogs
                                    .map((entry) => entry.toDiagnosticLine())
                                    .join('\n'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '日志只保留在内存中，最多 200 条；展示和复制前都会脱敏。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                key: const Key('copy-runtime-diagnostics-button'),
                onPressed: _copyRuntimeDiagnosticReport,
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: const Text('复制诊断'),
              ),
              TextButton.icon(
                key: const Key('export-runtime-diagnostics-button'),
                onPressed: _exportRuntimeDiagnosticReport,
                icon: const Icon(Icons.save_alt_outlined, size: 18),
                label: const Text('导出诊断'),
              ),
              TextButton(
                onPressed:
                    controller.canConfigureRuntime &&
                        !controller.runtimeChecking
                    ? () async {
                        final file = await openFile(
                          confirmButtonText: '使用此 Codex CLI',
                        );
                        if (file != null) {
                          await controller.setRuntimeExecutable(file.path);
                        }
                      }
                    : null,
                child: const Text('选择可执行文件'),
              ),
              if (controller.canConfigureRuntime)
                TextButton(
                  onPressed: controller.runtimeChecking
                      ? null
                      : controller.resetRuntimeExecutable,
                  child: const Text('恢复自动检测'),
                ),
              TextButton(
                onPressed: controller.runtimeChecking
                    ? null
                    : controller.inspectRuntime,
                child: const Text('重新检测'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 将当前脱敏运行时诊断复制到系统剪贴板，并提示用户可安全分享的范围。
  /// Copies the current redacted runtime diagnostics to the system clipboard and confirms the shareable scope.
  Future<void> _copyRuntimeDiagnosticReport() async {
    await Clipboard.setData(
      ClipboardData(text: _controller.buildRuntimeDiagnosticReport()),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制脱敏运行时诊断。')));
    }
  }

  /// 再次生成脱敏诊断报告并保存为用户选择的本地文本文件。
  /// Rebuilds the redacted diagnostic report and saves it as a user-selected local text file.
  Future<void> _exportRuntimeDiagnosticReport() async {
    final location = await getSaveLocation(
      suggestedName: 'codex-desk-diagnostics.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Text', extensions: ['txt']),
      ],
    );
    if (location == null) return;
    try {
      await File(
        location.path,
      ).writeAsString(_controller.buildRuntimeDiagnosticReport(), flush: true);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已导出脱敏运行时诊断。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出诊断失败：${error.toString()}')));
      }
    }
  }

  /// 请求新名称并重命名指定历史线程。
  /// Requests a new name and renames a specified history thread.
  Future<void> _renameThread(CodexThread thread) async {
    final name = TextEditingController(text: thread.name ?? thread.preview);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名任务'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: '任务名称'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(name.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    name.dispose();
    if (nextName != null && nextName.trim().isNotEmpty) {
      await _controller.renameThread(thread, nextName);
    }
  }

  /// 确认后归档指定历史线程。
  /// Archives a specified history thread after confirmation.
  Future<void> _archiveThread(CodexThread thread) async {
    await _archiveThreads([thread]);
  }

  /// 二次确认后批量归档历史线程，并返回实际成功归档的任务 ID。
  /// Archives multiple history threads after confirmation and returns the task IDs that actually archived.
  Future<Set<String>> _archiveThreads(List<CodexThread> threads) async {
    if (threads.isEmpty) return const <String>{};
    final count = threads.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(count == 1 ? '归档任务？' : '归档 $count 个任务？'),
        content: Text(
          count == 1
              ? '“${threads.single.title}”将从当前列表隐藏，但可以在后续归档视图中恢复。'
              : '所选任务将从当前列表隐藏，但可以在后续归档视图中恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true) return const <String>{};
    return _controller.archiveThreads(threads);
  }

  /// 二次确认后永久删除任务及 App Server 定义的派生任务，删除无法恢复。
  /// Permanently deletes a task and App Server-defined descendants after confirmation; deletion cannot be undone.
  Future<void> _deleteThread(CodexThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除任务？'),
        content: Text(
          '“${thread.title}”及其派生任务会从 Codex 中永久删除，无法恢复。本应用的对应本地缓存引用也会移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.deleteThread(thread);
  }

  /// 刷新并显示归档线程，允许用户恢复线程。
  /// Refreshes and shows archived threads, allowing the user to restore one.
  Future<void> _showArchivedThreads() async {
    await _controller.refreshArchivedThreads();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          return AlertDialog(
            title: const Text('已归档任务'),
            content: SizedBox(
              width: 480,
              height: 420,
              child: switch ((
                controller.archivedThreadsLoading,
                controller.archivedThreadsError,
                controller.archivedThreads,
              )) {
                (true, _, _) => const Center(
                  child: CircularProgressIndicator(),
                ),
                (_, final String error, _) => Center(child: Text(error)),
                (_, _, final List<CodexThread> threads) when threads.isEmpty =>
                  const Center(child: Text('暂无归档任务。')),
                (_, _, final List<CodexThread> threads) => ListView.separated(
                  itemCount: threads.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final thread = threads[index];
                    return _ArchivedThreadTile(
                      thread: thread,
                      enabled:
                          controller.status == RuntimeStatus.ready &&
                          !controller.isUnarchivingThread(thread.id) &&
                          !controller.isUpdatingThread(thread.id),
                      restoring: controller.isUnarchivingThread(thread.id),
                      onRestore: () => controller.unarchiveThread(thread),
                      onDelete: () => _deleteThread(thread),
                    );
                  },
                ),
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示当前任务收集到的文件变更和统一 Diff。
  /// Shows file changes and unified diff collected for the current task.
  Future<void> _showFileChanges() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) => AlertDialog(
          title: const Text('文件变更'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: _FileChangesList(
              changes: controller.fileChanges,
              turnDiff: controller.turnDiff,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开当前任务的代码审查视图；审查只读，不会提交或推送仓库。
  /// Opens the current task's read-only code-review surface without committing or pushing.
  Future<void> _showCodeReview() async {
    await _controller.ensureFileChangeDiffs();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) => _CodeReviewDialog(
          changes: controller.fileChanges,
          turnDiff: controller.turnDiff,
        ),
      ),
    );
  }

  /// 刷新并展示当前项目的 Git 状态和 Diff，以及用户显式触发的 Git 操作。
  /// Refreshes and shows the current project's Git state, diffs, and explicitly triggered Git actions.
  Future<void> _showGitProject() async {
    await _controller.refreshGitProject();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) =>
            _GitProjectDialog(controller: controller),
      ),
    );
  }

  /// 刷新并显示插件管理器，支持本地 marketplace 与启用状态。
  /// Refreshes and shows the plugin manager for local marketplaces and states.
  Future<void> _showPlugins() async {
    await _controller.refreshPlugins();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          final palette = YeknomPalette.of(context);
          return AlertDialog(
            key: const Key('plugin-manager-dialog'),
            title: const Text('Codex 插件'),
            content: SizedBox(
              width: 640,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('插件由本机 Codex CLI 管理；安装或启停后，应用会自动重连并用于后续新任务。'),
                  const SizedBox(height: 12),
                  if (controller.pluginsLoading || controller.pluginSaving)
                    const LinearProgressIndicator(),
                  if (controller.pluginActionProgress case final progress?) ...[
                    const SizedBox(height: 10),
                    Row(
                      key: const Key('plugin-action-progress'),
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(progress)),
                      ],
                    ),
                  ],
                  if (controller.pluginsError case final error?) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      key: const Key('plugin-action-error'),
                      style: TextStyle(color: palette.fault),
                    ),
                  ],
                  if (controller.pluginActionResult case final result?) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const Key('plugin-action-result'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: palette.ack.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.ack),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.restart_alt, size: 19),
                          const SizedBox(width: 8),
                          Expanded(child: Text(result)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: controller.pluginsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : controller.plugins.isEmpty
                        ? const Center(child: Text('没有已安装或可用的插件。'))
                        : ListView.separated(
                            itemCount: controller.plugins.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final plugin = controller.plugins[index];
                              return _PluginTile(
                                plugin: plugin,
                                busy: controller.pluginSaving,
                                active:
                                    controller.pluginActionTargetId ==
                                    plugin.id,
                                onEnabledChanged: (enabled) => controller
                                    .setPluginEnabled(plugin, enabled),
                                onInstall: () =>
                                    controller.installPlugin(plugin),
                                onRemove: () => _removePlugin(plugin),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: controller.pluginSaving ? null : _showAddMarketplace,
                icon: const Icon(Icons.add_link_outlined),
                label: const Text('添加来源'),
              ),
              TextButton.icon(
                onPressed: controller.pluginSaving ? null : _showMarketplaces,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('管理市场'),
              ),
              TextButton.icon(
                onPressed: controller.pluginsLoading || controller.pluginSaving
                    ? null
                    : controller.refreshPlugins,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 输入或选择一个本地/远程 marketplace 来源并交给控制器注册。
  /// Enters or chooses a local/remote marketplace source and registers it.
  Future<void> _showAddMarketplace() async {
    final source = TextEditingController();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加插件市场'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: source,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '本地目录、Git URL 或 owner/repo',
              hintText: 'example-org/codex-plugins',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final path = await getDirectoryPath(
                confirmButtonText: '选择本地 marketplace',
              );
              if (path != null && context.mounted) {
                Navigator.of(context).pop(path);
              }
            },
            child: const Text('选择本地目录'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(source.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    source.dispose();
    if (selected?.trim().isNotEmpty == true) {
      await _controller.addPluginMarketplace(selected!);
    }
  }

  /// 刷新并显示已配置 marketplace，支持 Git 更新与移除。
  /// Refreshes and shows configured marketplaces with Git updates and removal.
  Future<void> _showMarketplaces() async {
    await _controller.refreshMarketplaces();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ControllerBuilder(
        overrideController: widget.controller,
        builder: (context, controller) {
          final error = controller.marketplacesError;
          return AlertDialog(
            title: const Text('插件市场'),
            content: SizedBox(
              width: 640,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.pluginSaving) const LinearProgressIndicator(),
                  if (controller.pluginActionProgress case final progress?) ...[
                    const SizedBox(height: 10),
                    Text(
                      progress,
                      key: const Key('marketplace-action-progress'),
                    ),
                  ],
                  if (controller.pluginsError case final actionError?) ...[
                    const SizedBox(height: 10),
                    Text(
                      actionError,
                      style: TextStyle(color: YeknomPalette.of(context).fault),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: controller.marketplacesLoading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                        ? Center(child: Text(error))
                        : controller.marketplaces.isEmpty
                        ? const Center(child: Text('尚未配置插件市场。'))
                        : ListView.separated(
                            itemCount: controller.marketplaces.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final marketplace =
                                  controller.marketplaces[index];
                              return _MarketplaceTile(
                                marketplace: marketplace,
                                busy: controller.pluginSaving,
                                onUpgrade: () => controller
                                    .upgradePluginMarketplace(marketplace.name),
                                onRemove: () => _removeMarketplace(marketplace),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: controller.pluginSaving
                    ? null
                    : () => controller.upgradePluginMarketplace(null),
                icon: const Icon(Icons.system_update_outlined),
                label: const Text('刷新所有 Git 市场'),
              ),
              TextButton.icon(
                onPressed:
                    controller.marketplacesLoading || controller.pluginSaving
                    ? null
                    : controller.refreshMarketplaces,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 二次确认后移除 marketplace，避免误删已配置来源。
  /// Removes a marketplace after confirmation to avoid accidental source deletion.
  Future<void> _removeMarketplace(CodexMarketplace marketplace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除插件市场？'),
        content: Text('“${marketplace.name}”将不再提供可安装插件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.removePluginMarketplace(marketplace);
    }
  }

  /// 二次确认后卸载插件，连接器授权仍需在 Codex 中单独管理。
  /// Uninstalls a plugin after confirmation; connector authorization remains managed by Codex.
  Future<void> _removePlugin(CodexPlugin plugin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸载插件？'),
        content: Text('“${plugin.name}”的连接器授权不会随卸载自动移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.removePlugin(plugin);
  }

  /// 构建响应控制器状态的工作区主布局。
  /// Builds the main workspace layout in response to controller state.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? ref.watch(codexControllerProvider)!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              controller: controller,
              themeMode: widget.themeMode,
              themePreset: widget.themePreset,
              onThemeModeChanged: widget.onThemeModeChanged,
              onThemePresetChanged: widget.onThemePresetChanged,
              onChooseWorkspace: _showWorkspaceDirectories,
              onAccount: _showAccount,
              onCodexConfiguration: _showCodexConfiguration,
              onPlugins: _showPlugins,
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 980;
                  final sidebarMaximum =
                      (constraints.maxWidth -
                              (compact ? 360 : _inspectorWidth + 420))
                          .clamp(_minimumSidebarWidth, _maximumSidebarWidth)
                          .toDouble();
                  final inspectorMaximum =
                      (constraints.maxWidth - _sidebarWidth - 420)
                          .clamp(_minimumInspectorWidth, _maximumInspectorWidth)
                          .toDouble();
                  final sidebarWidth = _sidebarWidth
                      .clamp(_minimumSidebarWidth, sidebarMaximum)
                      .toDouble();
                  final inspectorWidth = _inspectorWidth
                      .clamp(_minimumInspectorWidth, inspectorMaximum)
                      .toDouble();
                  return Row(
                    children: [
                      _Sidebar(
                        width: sidebarWidth,
                        controller: controller,
                        onChooseWorkspace: _showWorkspaceDirectories,
                        onEditWorkspace: _showEditWorkspaceDialog,
                        onCreateWorkspace: () => unawaited(_createWorkspace()),
                        onConfigureRuntime: _showRuntime,
                        onRenameThread: _renameThread,
                        onArchiveThread: _archiveThread,
                        onArchiveThreads: _archiveThreads,
                        onDeleteThread: _deleteThread,
                        onShowArchivedThreads: _showArchivedThreads,
                        onExportHistory: _exportConversationHistory,
                        onImportHistory: _importConversationHistory,
                        onShowGitProject: _showGitProject,
                      ),
                      _PaneResizeHandle(
                        key: const Key('sidebar-resize-handle'),
                        onDragDelta: (delta) => setState(() {
                          _sidebarWidth = (_sidebarWidth + delta)
                              .clamp(_minimumSidebarWidth, sidebarMaximum)
                              .toDouble();
                        }),
                      ),
                      Expanded(
                        child: _ConversationPane(
                          controller: controller,
                          composer: _composer,
                          timelinePages: _timelinePages,
                          timelineScrollControllers: _timelineScrollControllers,
                          activeTimelinePageKey: _displayedThreadKey,
                          threadHistoryLoading: _threadHistoryLoading,
                          fileChangeSummaryExpanded: (pageKey) =>
                              _fileChangeSummaryExpanded[pageKey] ?? false,
                          onFileChangeSummaryExpandedChanged:
                              (pageKey, expanded) {
                                setState(() {
                                  _fileChangeSummaryExpanded[pageKey] =
                                      expanded;
                                });
                              },
                          activityExpanded: (pageKey, activityId) =>
                              _activityListExpanded['${pageKey.storageKey}/$activityId'] ??
                              true,
                          onActivityExpandedChanged:
                              (pageKey, activityId, expanded) {
                                setState(() {
                                  _activityListExpanded['${pageKey.storageKey}/$activityId'] =
                                      expanded;
                                });
                              },
                          onSend: _send,
                          onSteer: _steer,
                          onAdjustDirection: _adjustDirection,
                          onShowFileChanges: _showFileChanges,
                          onReview: _showCodeReview,
                        ),
                      ),
                      if (!compact) ...[
                        _PaneResizeHandle(
                          key: const Key('inspector-resize-handle'),
                          onDragDelta: (delta) => setState(() {
                            _inspectorWidth = (_inspectorWidth - delta)
                                .clamp(_minimumInspectorWidth, inspectorMaximum)
                                .toDouble();
                          }),
                        ),
                        _Inspector(
                          width: inspectorWidth,
                          controller: controller,
                          onShowGitProject: _showGitProject,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaneResizeHandle extends StatefulWidget {
  const _PaneResizeHandle({required this.onDragDelta, super.key});

  final ValueChanged<double> onDragDelta;

  /// 创建承载悬停与拖拽状态的分隔条 State。
  /// Creates the divider state that owns hover and drag feedback.
  @override
  State<_PaneResizeHandle> createState() => _PaneResizeHandleState();
}

class _PaneResizeHandleState extends State<_PaneResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  /// 构建桌面窗格的可拖拽分隔条，并在悬停或拖动时提高可见性。
  /// Builds a desktop pane divider that becomes more visible on hover or drag.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) =>
            widget.onDragDelta(details.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: SizedBox(
          width: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 2 : 1,
              color: active ? palette.active : palette.border,
            ),
          ),
        ),
      ),
    );
  }
}

String _workspaceDirectoryName(String path) {
  final normalized = path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  final separator = normalized.lastIndexOf(Platform.pathSeparator);
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

/// Displays the Codex-style project creation flow and accepts a source folder
/// from either the native picker or a desktop drop.
class _CreateWorkspaceDialog extends StatefulWidget {
  const _CreateWorkspaceDialog({required this.onCreate});

  final Future<bool> Function(String path, String name) onCreate;

  @override
  State<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<_CreateWorkspaceDialog> {
  final _nameController = TextEditingController();
  String? _sourceDirectory;
  bool _draggingDirectory = false;
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 打开系统目录选择器并更新弹窗中的源文件夹。
  /// Opens the native directory picker and updates the source folder in the dialog.
  Future<void> _chooseDirectory() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '选择文件夹');
      if (!mounted || path == null || path.trim().isEmpty) return;
      setState(() => _sourceDirectory = path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
    }
  }

  /// 接收桌面拖入的目录；文件或空路径会被拒绝并提示用户。
  /// Accepts a desktop-dropped directory and rejects files or empty paths with feedback.
  void _acceptDroppedDirectories(List<DropItem> items) {
    final directory = items.whereType<DropItemDirectory>().firstOrNull;
    if (directory == null || directory.path.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请拖入一个文件夹。')));
      return;
    }
    if (mounted) setState(() => _sourceDirectory = directory.path);
  }

  /// 校验源文件夹并创建工作区，成功后关闭弹窗。
  /// Validates the source folder, creates the workspace, and closes the dialog on success.
  Future<void> _createProject() async {
    final directory = _sourceDirectory;
    if (directory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先添加一个源文件夹。')));
      return;
    }
    setState(() => _creating = true);
    final created = await widget.onCreate(directory, _nameController.text);
    if (!mounted) return;
    if (created) {
      Navigator.of(context).pop();
    } else {
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final sourceDirectory = _sourceDirectory;
    final hasSourceDirectory = sourceDirectory != null;
    final sourceColor = _draggingDirectory ? palette.active : palette.border;
    return Dialog(
      key: const Key('create-workspace-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: palette.module,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 28, 32, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        key: const Key('create-workspace-dialog-title'),
                        '创建项目',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                      ),
                    ),
                    IconButton(
                      key: const Key('close-create-workspace-dialog'),
                      tooltip: '关闭',
                      onPressed: _creating
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 25),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                _WorkspaceNameField(
                  controller: _nameController,
                  hintText: '项目名称',
                  borderColor: palette.border,
                ),
                const SizedBox(height: 25),
                Text(
                  '源文件夹',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                DropTarget(
                  key: const Key('create-workspace-folder-drop-target'),
                  onDragEntered: (_) {
                    if (mounted) setState(() => _draggingDirectory = true);
                  },
                  onDragExited: (_) {
                    if (mounted) setState(() => _draggingDirectory = false);
                  },
                  onDragDone: (details) {
                    if (mounted) setState(() => _draggingDirectory = false);
                    _acceptDroppedDirectories(details.files);
                  },
                  child: Semantics(
                    button: true,
                    label: '添加 Codex 可读取和编辑的文件夹',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('create-workspace-folder-picker'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: _creating ? null : _chooseDirectory,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          constraints: const BoxConstraints(minHeight: 190),
                          decoration: BoxDecoration(
                            color: _draggingDirectory
                                ? Color.alphaBlend(
                                    palette.active.withValues(alpha: 0.08),
                                    palette.module,
                                  )
                                : palette.module,
                            border: Border.all(
                              color: sourceColor,
                              width: _draggingDirectory ? 1.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 24,
                              ),
                              child: hasSourceDirectory
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.folder_outlined,
                                          size: 31,
                                          color: palette.trace,
                                        ),
                                        const SizedBox(height: 12),
                                        Tooltip(
                                          message: sourceDirectory,
                                          child: Text(
                                            _workspaceDirectoryName(
                                              sourceDirectory,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: palette.trace,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '点击以更换文件夹',
                                          style: TextStyle(
                                            color: palette.muted,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _draggingDirectory
                                              ? Icons
                                                    .drive_folder_upload_outlined
                                              : Icons
                                                    .create_new_folder_outlined,
                                          size: 31,
                                          color: palette.muted,
                                        ),
                                        const SizedBox(height: 13),
                                        Text(
                                          _draggingDirectory
                                              ? '松开即可添加文件夹'
                                              : '添加 Codex 可读取和编辑的文件夹',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: palette.trace,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('cancel-create-workspace'),
                      onPressed: _creating
                          ? null
                          : () => Navigator.of(context).pop(),
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
                    const SizedBox(width: 20),
                    FilledButton(
                      key: const Key('create-workspace-confirm'),
                      onPressed: _creating ? null : _createProject,
                      style: FilledButton.styleFrom(
                        foregroundColor: palette.module,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: Text(
                        _creating ? '创建中…' : '创建项目',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
  }
}

class _WorkspaceNameField extends StatelessWidget {
  const _WorkspaceNameField({
    required this.controller,
    this.hintText,
    this.borderColor,
  });

  final TextEditingController controller;
  final String? hintText;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      height: 80,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor ?? palette.active, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Center(
              child: Icon(
                Icons.folder_outlined,
                size: 29,
                color: palette.trace,
              ),
            ),
          ),
          Container(width: 1, height: double.infinity, color: palette.border),
          Expanded(
            child: TextField(
              key: const Key('workspace-project-name-field'),
              controller: controller,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                // The surrounding container owns the field border. Explicitly
                // override every themed state border so the TextField cannot
                // render a second outline when focused.
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: hintText,
                contentPadding: EdgeInsets.symmetric(horizontal: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSourcesCard extends StatelessWidget {
  const _WorkspaceSourcesCard({
    required this.primary,
    required this.additional,
    required this.onRemovePrimary,
    required this.onRemoveAdditional,
    required this.onAdd,
  });

  final String primary;
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
            _WorkspaceSourceRow(
              path: primary,
              primary: true,
              onRemove: onRemovePrimary,
            ),
            for (final path in additional)
              _WorkspaceSourceRow(
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
                        color: palette.muted,
                      ),
                      const SizedBox(width: 17),
                      Text(
                        '添加文件夹',
                        style: TextStyle(
                          color: palette.trace,
                          fontSize: 18,
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

class _WorkspaceSourceRow extends StatelessWidget {
  const _WorkspaceSourceRow({
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
          Icon(Icons.folder_outlined, size: 27, color: palette.muted),
          const SizedBox(width: 17),
          Expanded(
            child: Tooltip(
              message: path,
              child: Text(
                _workspaceDirectoryName(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, color: palette.trace),
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
            icon: const Icon(Icons.close, size: 24),
            color: palette.muted,
          ),
        ],
      ),
    );
  }
}

/// 展示一个主目录或附加目录，并在窄窗口中安全截断路径。
/// Displays a primary or additional directory while safely truncating its path in narrow windows.
class _WorkspaceDirectoryTile extends StatelessWidget {
  const _WorkspaceDirectoryTile({
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.themeMode,
    required this.themePreset,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
    required this.onChooseWorkspace,
    required this.onAccount,
    required this.onCodexConfiguration,
    required this.onPlugins,
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

  /// 构建包含运行时、账户、Provider 和项目控制的顶部栏。
  /// Builds the top bar with runtime, account, provider, and workspace controls.
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1000;
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: palette.ack),
            const SizedBox(width: 10),
            Text('Codex Desk', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 16),
            _StatusPill(label: label, color: color),
            const Spacer(),
            PopupMenuButton<_ThemeAction>(
              tooltip:
                  '主题：${_themeModeLabel(themeMode)} · ${_themePresetLabel(themePreset)}',
              enabled:
                  onThemeModeChanged != null || onThemePresetChanged != null,
              icon: Icon(_themeModeIcon(themeMode)),
              onSelected: (action) {
                switch (action) {
                  case _ThemeAction.system:
                    onThemeModeChanged?.call(ThemeMode.system);
                  case _ThemeAction.light:
                    onThemeModeChanged?.call(ThemeMode.light);
                  case _ThemeAction.dark:
                    onThemeModeChanged?.call(ThemeMode.dark);
                  case _ThemeAction.workbench:
                    onThemePresetChanged?.call(YeknomColorPreset.workbench);
                  case _ThemeAction.cobalt:
                    onThemePresetChanged?.call(YeknomColorPreset.cobalt);
                  case _ThemeAction.orchid:
                    onThemePresetChanged?.call(YeknomColorPreset.orchid);
                  case _ThemeAction.graphite:
                    onThemePresetChanged?.call(YeknomColorPreset.graphite);
                  case _ThemeAction.obsidian:
                    onThemePresetChanged?.call(YeknomColorPreset.obsidian);
                  case _ThemeAction.midnight:
                    onThemePresetChanged?.call(YeknomColorPreset.midnight);
                  case _ThemeAction.blackberry:
                    onThemePresetChanged?.call(YeknomColorPreset.blackberry);
                  case _ThemeAction.sage:
                    onThemePresetChanged?.call(YeknomColorPreset.sage);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<_ThemeAction>(
                  enabled: false,
                  child: Text('显示模式'),
                ),
                CheckedPopupMenuItem(
                  key: const Key('theme-mode-system'),
                  value: _ThemeAction.system,
                  checked: themeMode == ThemeMode.system,
                  child: const Text('跟随系统'),
                ),
                CheckedPopupMenuItem(
                  key: const Key('theme-mode-light'),
                  value: _ThemeAction.light,
                  checked: themeMode == ThemeMode.light,
                  child: const Text('浅色'),
                ),
                CheckedPopupMenuItem(
                  key: const Key('theme-mode-dark'),
                  value: _ThemeAction.dark,
                  checked: themeMode == ThemeMode.dark,
                  child: const Text('深色'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<_ThemeAction>(
                  enabled: false,
                  child: Text('配色'),
                ),
                ..._ThemeAction.values
                    .where((action) => action.preset != null)
                    .map(
                      (action) => CheckedPopupMenuItem(
                        key: ValueKey('theme-preset-${action.preset!.name}'),
                        value: action,
                        checked: action.preset == themePreset,
                        child: Text(_themePresetLabel(action.preset!)),
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
        ),
      ),
    );
  }
}

/// 展示一个插件的来源、安装状态和可用操作。
/// Displays one plugin's source, install state, and available actions.
class _PluginTile extends StatelessWidget {
  const _PluginTile({
    required this.plugin,
    required this.busy,
    required this.active,
    required this.onEnabledChanged,
    required this.onInstall,
    required this.onRemove,
  });

  final CodexPlugin plugin;
  final bool busy;
  final bool active;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onInstall;
  final VoidCallback onRemove;

  /// 构建插件状态行，并只为已安装项显示启用开关。
  /// Builds the plugin state row and shows a toggle only for installed items.
  @override
  Widget build(BuildContext context) {
    final details = [
      plugin.sourceLabel,
      if (plugin.version?.isNotEmpty == true) 'v${plugin.version}',
      plugin.installPolicyLabel,
      plugin.authPolicyLabel,
    ].join(' · ');
    return ListTile(
      leading: Icon(
        plugin.installed ? Icons.extension : Icons.extension_outlined,
      ),
      title: Text(plugin.name),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: active
          ? const SizedBox(
              key: Key('plugin-tile-progress'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : plugin.installed
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: plugin.enabled,
                  onChanged: busy ? null : onEnabledChanged,
                ),
                IconButton(
                  tooltip: '卸载插件',
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : FilledButton.tonal(
              onPressed: busy ? null : onInstall,
              child: const Text('安装'),
            ),
    );
  }
}

/// 展示 marketplace 来源、类型以及其允许的维护操作。
/// Displays a marketplace source, type, and available maintenance actions.
class _MarketplaceTile extends StatelessWidget {
  const _MarketplaceTile({
    required this.marketplace,
    required this.busy,
    required this.onUpgrade,
    required this.onRemove,
  });

  final CodexMarketplace marketplace;
  final bool busy;
  final VoidCallback onUpgrade;
  final VoidCallback onRemove;

  /// 构建 marketplace 行；只为 Git 来源提供刷新操作。
  /// Builds the marketplace row and exposes refresh only for Git sources.
  @override
  Widget build(BuildContext context) {
    final source = marketplace.source?.isNotEmpty == true
        ? marketplace.source!
        : marketplace.root;
    return ListTile(
      leading: const Icon(Icons.storefront_outlined),
      title: Text(marketplace.name),
      subtitle: Text(
        '${marketplace.sourceTypeLabel} · $source',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (marketplace.sourceType == 'git')
            IconButton(
              tooltip: '刷新 Git 市场',
              onPressed: busy ? null : onUpgrade,
              icon: const Icon(Icons.system_update_outlined),
            ),
          IconButton(
            tooltip: '移除插件市场',
            onPressed: busy ? null : onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

/// 在侧栏中以 Codex 风格的项目节点展示一个可切换工作区。
/// Displays one switchable workspace as a compact Codex-style project node.
class _SidebarWorkspaceTile extends StatefulWidget {
  const _SidebarWorkspaceTile({
    required this.workspace,
    required this.active,
    required this.pinned,
    required this.enabled,
    required this.onTap,
    required this.onMore,
    required this.onEdit,
    required this.onHoverStart,
    required this.onHoverEnd,
    super.key,
  });

  final WorkspaceConfiguration workspace;
  final bool active;
  final bool pinned;
  final bool enabled;
  final VoidCallback onTap;
  final void Function(BuildContext context) onMore;
  final void Function(BuildContext context) onEdit;
  final void Function(BuildContext context) onHoverStart;
  final VoidCallback onHoverEnd;

  @override
  State<_SidebarWorkspaceTile> createState() => _SidebarWorkspaceTileState();
}

class _SidebarWorkspaceTileState extends State<_SidebarWorkspaceTile> {
  bool _hovering = false;

  /// 从主目录路径提取适合侧栏识别的工作区名称。
  /// Extracts a recognizable sidebar name from the primary-directory path.
  String get _displayName =>
      widget.workspace.name ??
      _workspaceDirectoryName(widget.workspace.primaryPath);

  /// 构建项目节点；完整路径只通过 tooltip 提供，不占用任务列表空间。
  /// Builds the project node; the full path is kept in a tooltip so task rows stay dense.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovering = true);
        widget.onHoverStart(context);
      },
      onExit: (_) {
        setState(() => _hovering = false);
        widget.onHoverEnd();
      },
      child: Semantics(
        selected: widget.active,
        button: !widget.active,
        label: widget.active ? '当前工作区 $_displayName' : '切换到工作区 $_displayName',
        child: Tooltip(
          message: widget.workspace.primaryPath,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _hovering ? palette.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: widget.active || !widget.enabled ? null : widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      widget.active
                          ? Icons.folder_special_outlined
                          : Icons.folder_outlined,
                      size: 19,
                      color: widget.active ? palette.active : palette.muted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.active ? palette.trace : palette.muted,
                          fontSize: 14,
                          fontWeight: widget.active
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.pinned)
                      Icon(Icons.push_pin, size: 13, color: palette.faint),
                    if (_hovering) ...[
                      IconButton(
                        key: ValueKey(
                          'sidebar-workspace-more-${widget.workspace.primaryPath}',
                        ),
                        tooltip: '项目菜单',
                        onPressed: () => widget.onMore(context),
                        icon: const Icon(Icons.more_horiz, size: 19),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        key: ValueKey(
                          'sidebar-workspace-edit-${widget.workspace.primaryPath}',
                        ),
                        tooltip: '新建任务',
                        onPressed: () => widget.onEdit(context),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ] else if (widget.workspace.additionalPaths.isNotEmpty)
                      Text(
                        '+${widget.workspace.additionalPaths.length}',
                        style: TextStyle(color: palette.faint, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧栏的低对比度分组标题，保留 Codex 的信息层级而不制造额外卡片。
/// A low-contrast sidebar section label that keeps Codex's hierarchy without extra cards.
class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: palette.faint,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
      ),
    );
  }
}

enum _WorkspaceAction { pin, edit, worktree, archive, remove }

class _WorkspaceDetailsCard extends StatelessWidget {
  const _WorkspaceDetailsCard({
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
                  const Icon(Icons.folder_outlined, size: 25),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      workspace.name ??
                          _workspaceDirectoryName(workspace.primaryPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: pinned ? '取消置顶项目' : '置顶项目',
                    onPressed: onTogglePin,
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 22,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            _WorkspaceDetailsRow(
              icon: Icons.chat_bubble_outline,
              label: taskCountLabel,
            ),
            Divider(height: 1, color: palette.border),
            for (final path in paths)
              _WorkspaceDetailsRow(
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
                    Icon(Icons.settings_outlined, size: 23),
                    SizedBox(width: 11),
                    Text(
                      '编辑项目',
                      style: TextStyle(
                        fontSize: 16,
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

class _WorkspaceDetailsRow extends StatelessWidget {
  const _WorkspaceDetailsRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 23),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.width,
    required this.controller,
    required this.onChooseWorkspace,
    required this.onEditWorkspace,
    required this.onCreateWorkspace,
    required this.onConfigureRuntime,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onArchiveThreads,
    required this.onDeleteThread,
    required this.onShowArchivedThreads,
    required this.onExportHistory,
    required this.onImportHistory,
    required this.onShowGitProject,
  });

  final double width;
  final CodexController controller;
  final VoidCallback onChooseWorkspace;
  final void Function(String primaryPath) onEditWorkspace;
  final VoidCallback onCreateWorkspace;
  final Future<void> Function() onConfigureRuntime;
  final Future<void> Function(CodexThread thread) onRenameThread;
  final Future<void> Function(CodexThread thread) onArchiveThread;
  final Future<Set<String>> Function(List<CodexThread> threads)
  onArchiveThreads;
  final Future<void> Function(CodexThread thread) onDeleteThread;
  final Future<void> Function() onShowArchivedThreads;
  final Future<void> Function() onExportHistory;
  final Future<void> Function() onImportHistory;
  final Future<void> Function() onShowGitProject;

  /// 创建管理侧栏搜索状态的 State 对象。
  /// Creates the State object that manages sidebar search state.
  @override
  State<_Sidebar> createState() => _SidebarState();
}

/// 缓存已访问工作区的任务列表，让切换项目只改变当前态而不会收起其他项目。
/// Keeps visited workspace task lists mounted in the tree when the active project changes.
class _WorkspaceThreadSnapshot {
  const _WorkspaceThreadSnapshot({
    required this.threads,
    required this.pinnedIds,
  });

  final List<CodexThread> threads;
  final Set<String> pinnedIds;
}

class _SidebarState extends State<_Sidebar> {
  final TextEditingController _threadSearch = TextEditingController();
  String _query = '';
  bool _batchMode = false;
  final Set<String> _selectedThreadIds = {};

  /// 已打开过的已完成任务；打开后不再重复显示完成提醒。
  /// Completed tasks acknowledged by opening them, so the reminder is not repeated.
  final Set<String> _acknowledgedCompletedThreadIds = {};
  final Map<String, int> _workspaceTaskCounts = {};
  final Map<String, _WorkspaceThreadSnapshot> _workspaceThreadSnapshots = {};
  OverlayEntry? _workspaceDetailsEntry;
  Timer? _workspaceDetailsHideTimer;

  /// 释放任务搜索输入控制器。
  /// Disposes the task-search text controller.
  @override
  void dispose() {
    _workspaceDetailsHideTimer?.cancel();
    _workspaceDetailsEntry?.remove();
    _threadSearch.dispose();
    super.dispose();
  }

  /// 将当前选中的活跃任务提交给带二次确认的批量归档操作。
  /// Sends selected active tasks to the confirmation-backed bulk archive action.
  Future<void> _archiveSelectedThreads(CodexController controller) async {
    final selected = controller.threads
        .where((thread) => _selectedThreadIds.contains(thread.id))
        .toList(growable: false);
    final archivedIds = await widget.onArchiveThreads(selected);
    if (!mounted) return;
    setState(() {
      _selectedThreadIds.removeAll(archivedIds);
      if (_selectedThreadIds.isEmpty && archivedIds.isNotEmpty) {
        _batchMode = false;
      }
    });
  }

  /// 在项目悬停时显示详情卡片；卡片本身也是可悬停的，便于把鼠标移入查看。
  /// Shows the hover detail card; the card keeps itself open while the pointer enters it.
  void _showWorkspaceDetails(
    BuildContext anchorContext,
    WorkspaceConfiguration workspace,
  ) {
    _workspaceDetailsHideTimer?.cancel();
    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox) return;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottomRight = renderObject.localToGlobal(
      Offset(renderObject.size.width, renderObject.size.height),
    );
    final controller = widget.controller;
    final isActive = workspace.primaryPath == controller.workspacePath;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final viewport = MediaQuery.sizeOf(context);
    const cardWidth = 340.0;
    final left = (bottomRight.dx + 6).clamp(
      8.0,
      viewport.width - cardWidth - 8,
    );
    final top = topLeft.dy.clamp(8.0, viewport.height - 280.0);
    _workspaceDetailsEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: left,
        top: top,
        width: cardWidth,
        child: MouseRegion(
          onEnter: (_) => _workspaceDetailsHideTimer?.cancel(),
          onExit: (_) => _scheduleWorkspaceDetailsHide(),
          child: _WorkspaceDetailsCard(
            workspace: workspace,
            taskCount: isActive
                ? controller.threads.length
                : _workspaceTaskCounts[workspace.primaryPath],
            pinned: controller.isWorkspacePinned(workspace.primaryPath),
            onTogglePin: () {
              unawaited(
                controller.toggleWorkspacePinned(workspace.primaryPath).then((
                  _,
                ) {
                  if (_workspaceDetailsEntry == entry) entry.markNeedsBuild();
                }),
              );
            },
            onEditProject: (_) {
              _hideWorkspaceDetails();
              widget.onEditWorkspace(workspace.primaryPath);
            },
          ),
        ),
      ),
    );
    _workspaceDetailsEntry = entry;
    overlay.insert(entry);
    if (!isActive && !_workspaceTaskCounts.containsKey(workspace.primaryPath)) {
      unawaited(_loadWorkspaceTaskCount(workspace.primaryPath, entry));
    }
  }

  Future<void> _loadWorkspaceTaskCount(String path, OverlayEntry entry) async {
    try {
      final count = await widget.controller.readWorkspaceTaskCount(path);
      if (!mounted || _workspaceDetailsEntry != entry) return;
      _workspaceTaskCounts[path] = count;
      entry.markNeedsBuild();
    } catch (_) {
      if (!mounted || _workspaceDetailsEntry != entry) return;
      _workspaceTaskCounts[path] = -1;
      entry.markNeedsBuild();
    }
  }

  void _scheduleWorkspaceDetailsHide() {
    _workspaceDetailsHideTimer?.cancel();
    _workspaceDetailsHideTimer = Timer(
      const Duration(milliseconds: 180),
      _hideWorkspaceDetails,
    );
  }

  void _hideWorkspaceDetails() {
    _workspaceDetailsHideTimer?.cancel();
    _workspaceDetailsEntry?.remove();
    _workspaceDetailsEntry = null;
  }

  /// 点击项目铅笔后显示项目操作菜单。
  /// Shows the project actions menu after clicking the pencil button.
  Future<void> _showWorkspaceActions(
    BuildContext anchorContext,
    WorkspaceConfiguration workspace,
  ) async {
    _hideWorkspaceDetails();
    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox) return;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottomRight = renderObject.localToGlobal(
      Offset(renderObject.size.width, renderObject.size.height),
    );
    final overlayRenderObject = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    if (overlayRenderObject is! RenderBox) return;
    final menuLeft = bottomRight.dx + 6;
    final action = await showMenu<_WorkspaceAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        menuLeft,
        topLeft.dy,
        overlayRenderObject.size.width - menuLeft,
        overlayRenderObject.size.height - bottomRight.dy,
      ),
      constraints: const BoxConstraints(minWidth: 235, maxWidth: 260),
      color: YeknomPalette.of(context).module,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: YeknomPalette.of(context).border),
      ),
      items: const [
        PopupMenuItem(
          value: _WorkspaceAction.pin,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.push_pin_outlined),
            title: Text('置顶'),
          ),
        ),
        PopupMenuItem(
          value: _WorkspaceAction.edit,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('编辑'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _WorkspaceAction.worktree,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.call_split_outlined),
            title: Text('创建永久工作树'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _WorkspaceAction.archive,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.archive_outlined),
            title: Text('归档聊天'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _WorkspaceAction.remove,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.close),
            title: Text('移除项目'),
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _WorkspaceAction.pin:
        await widget.controller.toggleWorkspacePinned(workspace.primaryPath);
      case _WorkspaceAction.edit:
        widget.onEditWorkspace(workspace.primaryPath);
      case _WorkspaceAction.worktree:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('永久工作树功能暂未接入。')));
      case _WorkspaceAction.archive:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请在任务菜单中归档聊天。')));
      case _WorkspaceAction.remove:
        await widget.controller.forgetWorkspace(workspace.primaryPath);
    }
  }

  /// 构建树中的任务文件节点；任务操作仍沿用原有菜单和批量选择行为。
  /// Builds a task-file node in the tree while preserving the existing actions.
  Widget _buildThreadNode(CodexController controller, CodexThread thread) {
    final indicator = _threadStatusIndicator(thread.status);
    final currentRunningThread =
        controller.activeThreadId == thread.id &&
        (controller.status == RuntimeStatus.running ||
            _isRunningThreadStatus(thread.status));
    return Padding(
      padding: const EdgeInsets.only(left: 25, right: 1),
      child: _HistoryThreadTile(
        thread: thread,
        selected: controller.activeThreadId == thread.id,
        pinned: controller.isThreadPinned(thread.id),
        statusIndicator:
            indicator == _ThreadStatusIndicator.completed &&
                _acknowledgedCompletedThreadIds.contains(thread.id)
            ? null
            : indicator,
        running: currentRunningThread,
        enabled:
            (controller.status == RuntimeStatus.ready ||
                currentRunningThread) &&
            !controller.isUpdatingThread(thread.id),
        selectionMode: _batchMode,
        batchSelected: _selectedThreadIds.contains(thread.id),
        onTap: () {
          // The active row remains clickable for focus/feedback while its
          // turn runs, but must not attempt to resume or replace the thread.
          if (currentRunningThread) return;
          if (_batchMode) {
            setState(() {
              if (!_selectedThreadIds.add(thread.id)) {
                _selectedThreadIds.remove(thread.id);
              }
            });
          } else {
            if (indicator == _ThreadStatusIndicator.completed) {
              setState(() {
                _acknowledgedCompletedThreadIds.add(thread.id);
              });
            }
            controller.resumeThread(thread);
          }
        },
        onRename: () => widget.onRenameThread(thread),
        onArchive: () => widget.onArchiveThread(thread),
        onDelete: () => widget.onDeleteThread(thread),
        onTogglePin: () => controller.toggleThreadPinned(thread),
      ),
    );
  }

  /// 构建工作区选择、线程历史和 CLI 配置侧栏。
  /// Builds the sidebar for workspace selection, thread history, and CLI setup.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final controller = widget.controller;
    final activePath = controller.workspacePath;
    if (activePath != null &&
        (!controller.threadsLoading ||
            !_workspaceThreadSnapshots.containsKey(activePath))) {
      _workspaceThreadSnapshots[activePath] = _WorkspaceThreadSnapshot(
        threads: List.unmodifiable(controller.threads),
        pinnedIds: Set.unmodifiable(controller.pinnedThreadIds),
      );
    }
    final query = _query.trim().toLowerCase();
    final activeSnapshot = activePath == null
        ? null
        : _workspaceThreadSnapshots[activePath];
    final filteredThreads = (activeSnapshot?.threads ?? controller.threads)
        .where(
          (thread) =>
              query.isEmpty ||
              thread.title.toLowerCase().contains(query) ||
              thread.preview.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final visibleThreads = [
      ...filteredThreads.where(
        (thread) => controller.isThreadPinned(thread.id),
      ),
      ...filteredThreads.where(
        (thread) => !controller.isThreadPinned(thread.id),
      ),
    ];
    final hasPinnedThreads = filteredThreads.any((thread) {
      return activeSnapshot?.pinnedIds.contains(thread.id) ??
          controller.isThreadPinned(thread.id);
    });
    final pinnedThreads = visibleThreads
        .where(
          (thread) =>
              activeSnapshot?.pinnedIds.contains(thread.id) ??
              controller.isThreadPinned(thread.id),
        )
        .toList(growable: false);
    // 保持用户创建工作区时的顺序；切换只改变选中态，不重排列表。
    // Preserve creation order; switching changes selection without reordering the list.
    final configuredWorkspaces = controller.workspaceConfigurations;
    // 测试注入或旧缓存可能只有当前路径而没有工作区记录；仍将它作为树根，
    // 避免任务从层级结构中消失。
    // Test injections and older caches may only provide the current path; keep it as the tree root.
    final workspaces = configuredWorkspaces.isNotEmpty
        ? configuredWorkspaces
        : controller.workspacePath == null
        ? const <WorkspaceConfiguration>[]
        : [WorkspaceConfiguration(primaryPath: controller.workspacePath!)];
    final workspaceThreadsByPath = <String, List<CodexThread>>{};
    final workspaceProjectThreadsByPath = <String, List<CodexThread>>{};
    for (final workspace in workspaces) {
      final snapshot = _workspaceThreadSnapshots[workspace.primaryPath];
      final threads = workspace.primaryPath == activePath
          ? (activeSnapshot?.threads ?? controller.threads)
          : (snapshot?.threads ?? const <CodexThread>[]);
      final pinnedIds = workspace.primaryPath == activePath
          ? (activeSnapshot?.pinnedIds ?? controller.pinnedThreadIds)
          : (snapshot?.pinnedIds ?? const <String>{});
      workspaceThreadsByPath[workspace.primaryPath] = threads;
      workspaceProjectThreadsByPath[workspace.primaryPath] = threads
          .where(
            (thread) =>
                (workspace.primaryPath != activePath ||
                    !pinnedIds.contains(thread.id)) &&
                (query.isEmpty ||
                    thread.title.toLowerCase().contains(query) ||
                    thread.preview.toLowerCase().contains(query)),
          )
          .toList(growable: false);
    }
    return SizedBox(
      key: const Key('sidebar-pane'),
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '项目',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.15,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('sidebar-create-workspace-button'),
                  tooltip: '新建工作区',
                  visualDensity: VisualDensity.compact,
                  onPressed: controller.canChangePrimaryWorkspace
                      ? widget.onCreateWorkspace
                      : null,
                  icon: const Icon(Icons.add, size: 19),
                ),
                IconButton(
                  key: const Key('sidebar-manage-workspaces-button'),
                  tooltip: '管理工作区',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onChooseWorkspace,
                  icon: const Icon(Icons.tune, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                IconButton(
                  tooltip: '新建任务',
                  onPressed: controller.canSend
                      ? controller.createThread
                      : null,
                  icon: const Icon(Icons.add, size: 20),
                ),
                IconButton(
                  tooltip: '刷新任务列表',
                  onPressed: controller.canSend && !controller.threadsLoading
                      ? controller.refreshThreads
                      : null,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                PopupMenuButton<_HistoryAction>(
                  tooltip: '本地历史',
                  enabled: controller.workspacePath != null,
                  icon: const Icon(Icons.inventory_2_outlined, size: 20),
                  onSelected: (action) async {
                    switch (action) {
                      case _HistoryAction.archived:
                        await widget.onShowArchivedThreads();
                      case _HistoryAction.batchArchive:
                        setState(() => _batchMode = true);
                      case _HistoryAction.export:
                        await widget.onExportHistory();
                      case _HistoryAction.import:
                        await widget.onImportHistory();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _HistoryAction.archived,
                      child: ListTile(
                        leading: Icon(Icons.inventory_2_outlined),
                        title: Text('已归档任务'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HistoryAction.batchArchive,
                      child: ListTile(
                        leading: Icon(Icons.checklist_outlined),
                        title: Text('批量归档任务'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HistoryAction.export,
                      child: ListTile(
                        leading: Icon(Icons.file_upload_outlined),
                        title: Text('导出本地历史'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HistoryAction.import,
                      child: ListTile(
                        leading: Icon(Icons.file_download_outlined),
                        title: Text('导入到当前项目'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 5),
            if (_batchMode) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('已选 ${_selectedThreadIds.length} 个任务'),
                  TextButton(
                    onPressed: () => setState(() {
                      _batchMode = false;
                      _selectedThreadIds.clear();
                    }),
                    child: const Text('取消'),
                  ),
                  FilledButton.tonal(
                    onPressed:
                        _selectedThreadIds.isEmpty ||
                            controller.status != RuntimeStatus.ready
                        ? null
                        : () => _archiveSelectedThreads(controller),
                    child: const Text('归档已选'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              key: const Key('thread-search-field'),
              controller: _threadSearch,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索任务',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _threadSearch.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            if (controller.threadsLoading && controller.threads.isEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (controller.threadsLoading && controller.threads.isEmpty)
              const SizedBox(height: 6),
            Expanded(
              child: Ink(
                key: const Key('workspace-picker-surface'),
                decoration: BoxDecoration(
                  color: workspaces.isEmpty
                      ? palette.raised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: workspaces.isEmpty
                      ? InkWell(
                          key: const Key('sidebar-workspace-empty'),
                          onTap: controller.canChangePrimaryWorkspace
                              ? widget.onCreateWorkspace
                              : null,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.create_new_folder_outlined,
                                  size: 19,
                                ),
                                SizedBox(width: 9),
                                Expanded(child: Text('新建第一个工作区')),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          children: [
                            if (hasPinnedThreads) ...[
                              const _SidebarSectionLabel(label: '置顶'),
                              const SizedBox(height: 2),
                              for (final thread in pinnedThreads) ...[
                                _buildThreadNode(controller, thread),
                                const SizedBox(height: 1),
                              ],
                              const SizedBox(height: 12),
                            ],
                            for (final workspace in workspaces) ...[
                              _SidebarWorkspaceTile(
                                key: ValueKey(
                                  'sidebar-workspace-${workspace.primaryPath}',
                                ),
                                workspace: workspace,
                                active:
                                    workspace.primaryPath ==
                                    controller.workspacePath,
                                pinned: controller.isWorkspacePinned(
                                  workspace.primaryPath,
                                ),
                                enabled: controller.canChangePrimaryWorkspace,
                                onTap: () => unawaited(
                                  controller.selectWorkspaceAndReconnect(
                                    workspace.primaryPath,
                                  ),
                                ),
                                onMore: (anchorContext) =>
                                    _showWorkspaceActions(
                                      anchorContext,
                                      workspace,
                                    ),
                                onEdit: (_) => controller.createThread(),
                                onHoverStart: (anchorContext) =>
                                    _showWorkspaceDetails(
                                      anchorContext,
                                      workspace,
                                    ),
                                onHoverEnd: _scheduleWorkspaceDetailsHide,
                              ),
                              if (workspace.primaryPath == activePath) ...[
                                if (controller.threadsError case final error?)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 34,
                                      top: 4,
                                    ),
                                    child: _MutedText(error),
                                  )
                                else if (workspaceProjectThreadsByPath[workspace
                                            .primaryPath]!
                                        .isEmpty &&
                                    workspaceThreadsByPath[workspace
                                            .primaryPath]!
                                        .isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 34, top: 4),
                                    child: _MutedText('暂无历史任务；发送第一条消息后会创建。'),
                                  )
                                else if (workspaceProjectThreadsByPath[workspace
                                        .primaryPath]!
                                    .isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 34, top: 4),
                                    child: _MutedText('没有匹配的任务。'),
                                  )
                                else
                                  for (final thread
                                      in workspaceProjectThreadsByPath[workspace
                                          .primaryPath]!) ...[
                                    _buildThreadNode(controller, thread),
                                    const SizedBox(height: 1),
                                  ],
                              ] else if (_workspaceThreadSnapshots.containsKey(
                                workspace.primaryPath,
                              )) ...[
                                for (final thread
                                    in workspaceProjectThreadsByPath[workspace
                                        .primaryPath]!) ...[
                                  _buildThreadNode(controller, thread),
                                  const SizedBox(height: 1),
                                ],
                              ],
                              const SizedBox(height: 5),
                            ],
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onConfigureRuntime,
              icon: const Icon(Icons.memory_outlined, size: 18),
              label: const Text('Codex CLI'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.workspacePath == null
                  ? null
                  : widget.onShowGitProject,
              icon: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('Git 项目'),
            ),
            const SizedBox(height: 10),
            const _MutedText('本地优先 · stdio JSON-RPC'),
          ],
        ),
      ),
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.controller,
    required this.composer,
    required this.timelinePages,
    required this.timelineScrollControllers,
    required this.activeTimelinePageKey,
    required this.threadHistoryLoading,
    required this.fileChangeSummaryExpanded,
    required this.onFileChangeSummaryExpandedChanged,
    required this.activityExpanded,
    required this.onActivityExpandedChanged,
    required this.onSend,
    required this.onSteer,
    required this.onAdjustDirection,
    required this.onShowFileChanges,
    required this.onReview,
  });

  final CodexController controller;
  final TextEditingController composer;
  final Map<_ThreadViewportKey, _TimelinePageData> timelinePages;
  final Map<_ThreadViewportKey, ScrollController> timelineScrollControllers;
  final _ThreadViewportKey activeTimelinePageKey;
  final bool threadHistoryLoading;
  final bool Function(_ThreadViewportKey pageKey) fileChangeSummaryExpanded;
  final void Function(_ThreadViewportKey pageKey, bool expanded)
  onFileChangeSummaryExpandedChanged;
  final bool Function(_ThreadViewportKey pageKey, String activityId)
  activityExpanded;
  final void Function(
    _ThreadViewportKey pageKey,
    String activityId,
    bool expanded,
  )
  onActivityExpandedChanged;
  final Future<bool> Function(_ComposerSubmission submission) onSend;
  final Future<bool> Function(_ComposerSubmission submission) onSteer;
  final Future<void> Function(String originalPrompt) onAdjustDirection;
  final Future<void> Function() onShowFileChanges;
  final Future<void> Function() onReview;

  /// 构建时间线、审批提示和任务输入区域。
  /// Builds the timeline, approval prompt, and task composer area.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showProvider = constraints.maxWidth >= 360;
              final showSandbox = constraints.maxWidth >= 560;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      '任务控制台',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (showProvider) ...[
                    _ProviderChip(
                      label: '${controller.providerLabel} / App Server',
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (showSandbox) ...[
                    const _ProviderChip(label: 'workspace-write'),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    tooltip: '查看文件变更',
                    onPressed: onShowFileChanges,
                    icon: const Icon(Icons.difference_outlined, size: 19),
                  ),
                ],
              );
            },
          ),
        ),
        if (controller.lastError case final error?)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.fault.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(error, style: TextStyle(color: palette.fault)),
          ),
        if (controller.pendingApproval case final approval?)
          _ApprovalPanel(
            approval: approval,
            enabled: controller.canRespondToApproval,
            onAccept: () => controller.respondToApproval(accepted: true),
            onDecline: () => controller.respondToApproval(accepted: false),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final plan = controller.status == RuntimeStatus.running
                  ? controller.activeTaskPlan
                  : null;
              final planHeight = (constraints.maxHeight - 16).clamp(
                100.0,
                340.0,
              );
              final pages = timelinePages.entries.toList(growable: false);
              final activePageIndex = pages.indexWhere(
                (page) => page.key == activeTimelinePageKey,
              );
              return Stack(
                children: [
                  IndexedStack(
                    index: activePageIndex < 0 ? 0 : activePageIndex,
                    children: [
                      for (final page in pages)
                        _ConversationTimeline(
                          key: ValueKey(
                            'conversation-timeline-${page.key.storageKey}',
                          ),
                          pageKey: page.key,
                          data: page.value,
                          scrollController:
                              timelineScrollControllers[page.key]!,
                          bottomPadding:
                              page.key == activeTimelinePageKey && plan != null
                              ? planHeight + 28
                              : 12,
                          active: page.key == activeTimelinePageKey,
                          fileChangeSummaryExpanded: fileChangeSummaryExpanded(
                            page.key,
                          ),
                          onFileChangeSummaryExpandedChanged: (expanded) =>
                              onFileChangeSummaryExpandedChanged(
                                page.key,
                                expanded,
                              ),
                          activityExpanded: (activityId) =>
                              activityExpanded(page.key, activityId),
                          onActivityExpandedChanged: (activityId, expanded) =>
                              onActivityExpandedChanged(
                                page.key,
                                activityId,
                                expanded,
                              ),
                          onAdjustDirection: onAdjustDirection,
                          onReview: onReview,
                        ),
                    ],
                  ),
                  if (plan != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 620,
                            maxHeight: planHeight,
                          ),
                          child: _TaskPlanPanel(plan: plan),
                        ),
                      ),
                    ),
                  if (threadHistoryLoading)
                    Positioned.fill(
                      child: ColoredBox(
                        key: const Key('thread-history-loading'),
                        color: palette.module,
                        child: const Center(child: _CodexLoadingMark()),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        _ComposerPanel(
          key: const Key('composer-panel'),
          controller: controller,
          composer: composer,
          onSend: onSend,
          onSteer: onSteer,
        ),
      ],
    );
  }
}

/// Immutable rendering inputs for one retained task timeline.
/// 单个保活任务时间线的不可变渲染输入。
class _TimelinePageData {
  const _TimelinePageData({
    required this.entries,
    required this.fileChanges,
    required this.turnDiff,
    required this.showFileChangeSummary,
    required this.canSteer,
  });

  final List<TimelineEntry> entries;
  final List<CodexFileChange> fileChanges;
  final String? turnDiff;
  final bool showFileChangeSummary;
  final bool canSteer;
}

/// A task timeline that remains mounted inside the page cache.
/// 在页面缓存中持续挂载的任务时间线。
class _ConversationTimeline extends StatelessWidget {
  const _ConversationTimeline({
    required this.pageKey,
    required this.data,
    required this.scrollController,
    required this.bottomPadding,
    required this.active,
    required this.fileChangeSummaryExpanded,
    required this.onFileChangeSummaryExpandedChanged,
    required this.activityExpanded,
    required this.onActivityExpandedChanged,
    required this.onAdjustDirection,
    required this.onReview,
    super.key,
  });

  final _ThreadViewportKey pageKey;
  final _TimelinePageData data;
  final ScrollController scrollController;
  final double bottomPadding;
  final bool active;
  final bool fileChangeSummaryExpanded;
  final ValueChanged<bool> onFileChangeSummaryExpandedChanged;
  final bool Function(String activityId) activityExpanded;
  final void Function(String activityId, bool expanded)
  onActivityExpandedChanged;
  final Future<void> Function(String originalPrompt) onAdjustDirection;
  final Future<void> Function() onReview;

  @override
  Widget build(BuildContext context) {
    final latestUserIndex = data.entries.lastIndexWhere(
      (entry) => entry.kind == TimelineKind.user,
    );
    final timelineItems = _conversationTimelineItems(data.entries);
    return ListView.separated(
      key: PageStorageKey('conversation-timeline-${pageKey.storageKey}'),
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(24, 12, 24, bottomPadding),
      itemCount: timelineItems.length + (data.showFileChangeSummary ? 1 : 0),
      separatorBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Divider(height: 1),
      ),
      itemBuilder: (context, index) {
        if (index == timelineItems.length) {
          return _FileChangeSummaryCard(
            key: ValueKey('file-change-summary-${pageKey.storageKey}'),
            changes: data.fileChanges,
            turnDiff: data.turnDiff,
            expanded: fileChangeSummaryExpanded,
            onExpandedChanged: onFileChangeSummaryExpandedChanged,
            onReview: onReview,
          );
        }
        final item = timelineItems[index];
        if (item.activities case final activities?) {
          final activityId = item.entryIndex.toString();
          return _TimelineActivityList(
            key: ValueKey(
              'timeline-activity-${pageKey.storageKey}-$activityId',
            ),
            entries: activities,
            expanded: activityExpanded(activityId),
            onExpandedChanged: (expanded) =>
                onActivityExpandedChanged(activityId, expanded),
          );
        }
        final entry = item.entry!;
        return _TimelineEntry(
          entry,
          onAdjustDirection:
              active &&
                  data.canSteer &&
                  item.entryIndex == latestUserIndex &&
                  entry.kind == TimelineKind.user
              ? () => onAdjustDirection(entry.detail)
              : null,
        );
      },
    );
  }
}

/// Codex-style quiet loading surface: a centered, monochrome knot with no
/// text or animated layout movement while a task history is being restored.
/// Codex 风格的安静加载画面：居中的单色结标志，不引入文字或布局动画。
class _CodexLoadingMark extends StatelessWidget {
  const _CodexLoadingMark();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 62,
    height: 62,
    child: CustomPaint(painter: _CodexLoadingMarkPainter()),
  );
}

class _CodexLoadingMarkPainter extends CustomPainter {
  const _CodexLoadingMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.29;
    final stroke = Paint()
      ..color = const Color(0xFF9B9B9B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.105
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var index = 0; index < 6; index++) {
      final angle = index * 3.141592653589793 / 3;
      final start = Offset(
        center.dx + radius * 0.55 * _cos(angle),
        center.dy + radius * 0.55 * _sin(angle),
      );
      final path = Path()..moveTo(start.dx, start.dy);
      path.cubicTo(
        center.dx + radius * 1.26 * _cos(angle - 0.65),
        center.dy + radius * 1.26 * _sin(angle - 0.65),
        center.dx + radius * 1.26 * _cos(angle + 0.65),
        center.dy + radius * 1.26 * _sin(angle + 0.65),
        start.dx,
        start.dy,
      );
      canvas.drawPath(path, stroke);
    }
  }

  double _cos(double value) => math.cos(value);
  double _sin(double value) => math.sin(value);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DiffStats {
  const _DiffStats(this.additions, this.deletions);

  final int additions;
  final int deletions;

  _DiffStats operator +(_DiffStats other) =>
      _DiffStats(additions + other.additions, deletions + other.deletions);
}

_DiffStats _diffStats(String diff) {
  var additions = 0;
  var deletions = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+++') || line.startsWith('---')) continue;
    if (line.startsWith('+')) additions++;
    if (line.startsWith('-')) deletions++;
  }
  return _DiffStats(additions, deletions);
}

String _diffCountLabel(String prefix, int count, {required bool unknown}) =>
    unknown ? '$prefix?' : '$prefix$count';

class _FileChangeSummaryCard extends StatelessWidget {
  const _FileChangeSummaryCard({
    required this.changes,
    required this.turnDiff,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onReview,
    super.key,
  });

  final List<CodexFileChange> changes;
  final String? turnDiff;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final Future<void> Function() onReview;

  _DiffStats get _stats {
    final stats = changes.fold(
      const _DiffStats(0, 0),
      (total, change) => total + _diffStats(change.diff),
    );
    final fallback = turnDiff;
    final hasMissingDiff = changes.any((change) => change.diff.trim().isEmpty);
    return hasMissingDiff && fallback != null && fallback.isNotEmpty
        ? _diffStats(fallback)
        : stats;
  }

  bool get _statsUnknown =>
      changes.any((change) => change.diff.trim().isEmpty) &&
      (turnDiff == null || turnDiff!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _stats;
    final visibleChanges = expanded
        ? changes
        : changes.take(3).toList(growable: false);
    final hiddenCount = changes.length - visibleChanges.length;
    return Container(
      key: const Key('file-change-summary-card'),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.field,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.edit_note_outlined, color: palette.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已编辑 ${changes.length} 个文件',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _diffCountLabel(
                                '+',
                                stats.additions,
                                unknown: _statsUnknown,
                              ),
                              style: TextStyle(color: palette.ack),
                            ),
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: _diffCountLabel(
                                '-',
                                stats.deletions,
                                unknown: _statsUnknown,
                              ),
                              style: TextStyle(color: palette.fault),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  key: const Key('review-file-changes-button'),
                  onPressed: () => unawaited(onReview()),
                  child: const Text('审核'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          for (final change in visibleChanges)
            _FileChangeSummaryRow(
              change: change,
              fallbackDiff: changes.length == 1 ? turnDiff : null,
            ),
          if (hiddenCount > 0 || expanded && changes.length > 3)
            InkWell(
              onTap: () => onExpandedChanged(!expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Text(
                      expanded ? '收起文件' : '再显示 $hiddenCount 个文件',
                      style: TextStyle(color: palette.muted),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: palette.muted,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileChangeSummaryRow extends StatefulWidget {
  const _FileChangeSummaryRow({required this.change, this.fallbackDiff});

  final CodexFileChange change;
  final String? fallbackDiff;

  @override
  State<_FileChangeSummaryRow> createState() => _FileChangeSummaryRowState();
}

class _FileChangeSummaryRowState extends State<_FileChangeSummaryRow> {
  static const _previewMargin = 12.0;
  static const _previewGap = 8.0;
  static const _previewMaxWidth = 560.0;
  static const _previewMaxHeight = 330.0;

  final LayerLink _layerLink = LayerLink();
  final ValueNotifier<int> _previewVersion = ValueNotifier(0);
  OverlayEntry? _previewEntry;
  Timer? _hideTimer;
  bool _hovering = false;
  Offset _previewOffset = Offset.zero;
  Alignment _targetAnchor = Alignment.topLeft;
  Alignment _followerAnchor = Alignment.bottomLeft;
  double _previewWidth = _previewMaxWidth;
  double _previewMaxHeightValue = _previewMaxHeight;
  double _previewHeight = _previewMaxHeight;
  bool _previewRefreshScheduled = false;

  String get _diff => widget.change.diff.trim().isEmpty
      ? (widget.fallbackDiff ?? '')
      : widget.change.diff;

  bool _updatePreviewGeometry() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return false;
    final viewport = MediaQuery.sizeOf(context);
    final targetTopLeft = renderObject.localToGlobal(Offset.zero);
    final targetBottom = targetTopLeft.dy + renderObject.size.height;
    final availableAbove = targetTopLeft.dy - _previewMargin - _previewGap;
    final availableBelow =
        viewport.height - targetBottom - _previewMargin - _previewGap;
    final showAbove = availableAbove >= availableBelow;
    final availableHeight = showAbove ? availableAbove : availableBelow;
    final width = (viewport.width - _previewMargin * 2)
        .clamp(1.0, _previewMaxWidth)
        .toDouble();
    final horizontalShift =
        targetTopLeft.dx + width > viewport.width - _previewMargin
        ? viewport.width - _previewMargin - targetTopLeft.dx - width
        : targetTopLeft.dx < _previewMargin
        ? _previewMargin - targetTopLeft.dx
        : 0.0;
    _previewWidth = width;
    _previewMaxHeightValue = availableHeight
        .clamp(1.0, _previewMaxHeight)
        .toDouble();
    final previewLineCount = _previewLines(_diff).length;
    final estimatedHeight = _diff.trim().isEmpty
        ? 96.0
        : 60.0 +
              (previewLineCount > 12 ? 12 : previewLineCount) * 18.0 +
              (previewLineCount > 12 ? 24.0 : 0.0);
    _previewHeight = estimatedHeight < _previewMaxHeightValue
        ? estimatedHeight
        : _previewMaxHeightValue;
    _previewOffset = Offset(
      horizontalShift,
      showAbove
          ? -_previewHeight - _previewGap
          : renderObject.size.height + _previewGap,
    );
    _targetAnchor = Alignment.topLeft;
    _followerAnchor = Alignment.topLeft;
    return true;
  }

  void _showPreview() {
    _hideTimer?.cancel();
    if (_previewEntry != null || !mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || !_updatePreviewGeometry()) return;

    final entry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<int>(
        valueListenable: _previewVersion,
        builder: (context, _, _) => CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: _targetAnchor,
          followerAnchor: _followerAnchor,
          offset: _previewOffset,
          child: IgnorePointer(
            child: UnconstrainedBox(
              alignment: Alignment.topLeft,
              child: _FileChangeHoverPreview(
                path: widget.change.path,
                diff: _diff,
                width: _previewWidth,
                maxHeight: _previewMaxHeightValue,
                height: _previewHeight,
              ),
            ),
          ),
        ),
      ),
    );
    _previewEntry = entry;
    overlay.insert(entry);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      _previewEntry?.remove();
      _previewEntry = null;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _previewEntry?.remove();
    _previewVersion.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _FileChangeSummaryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.change.path != widget.change.path ||
        oldWidget.change.diff != widget.change.diff ||
        oldWidget.fallbackDiff != widget.fallbackDiff) {
      if (_previewEntry != null && !_previewRefreshScheduled) {
        _previewRefreshScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _previewRefreshScheduled = false;
          if (mounted && _previewEntry != null) {
            _updatePreviewGeometry();
            _previewVersion.value++;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _diffStats(_diff);
    final unknown = _diff.trim().isEmpty;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        key: ValueKey('file-change-row-${widget.change.path}'),
        onEnter: (_) {
          setState(() => _hovering = true);
          _showPreview();
        },
        onExit: (_) {
          setState(() => _hovering = false);
          _scheduleHide();
        },
        cursor: SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: palette.field.withValues(alpha: _hovering ? 0.68 : 0.42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.change.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.trace),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _diffCountLabel('+', stats.additions, unknown: unknown),
                style: TextStyle(color: palette.ack),
              ),
              const SizedBox(width: 10),
              Text(
                _diffCountLabel('-', stats.deletions, unknown: unknown),
                style: TextStyle(color: palette.fault),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffPreviewLine {
  const _DiffPreviewLine(this.text, this.lineNumber);

  final String text;
  final int? lineNumber;
}

List<_DiffPreviewLine> _previewLines(String diff) {
  final hunkPattern = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
  var inHunk = false;
  var oldLine = 0;
  var newLine = 0;
  return diff
      .split('\n')
      .map((line) {
        final hunk = hunkPattern.firstMatch(line);
        if (hunk != null) {
          inHunk = true;
          oldLine = int.parse(hunk.group(1)!);
          newLine = int.parse(hunk.group(2)!);
          return _DiffPreviewLine(line, null);
        }
        if (!inHunk) return _DiffPreviewLine(line, null);

        if (line.startsWith('+') && !line.startsWith('+++')) {
          return _DiffPreviewLine(line, newLine++);
        }
        if (line.startsWith('-') && !line.startsWith('---')) {
          return _DiffPreviewLine(line, oldLine++);
        }
        if (line.startsWith(' ')) {
          final number = newLine++;
          oldLine++;
          return _DiffPreviewLine(line, number);
        }
        return _DiffPreviewLine(line, null);
      })
      .toList(growable: false);
}

class _FileChangeHoverPreview extends StatelessWidget {
  const _FileChangeHoverPreview({
    required this.path,
    required this.diff,
    required this.width,
    required this.maxHeight,
    required this.height,
  });

  final String path;
  final String diff;
  final double width;
  final double maxHeight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _diffStats(diff);
    final lines = _previewLines(diff);
    final visibleLines = lines.length > 12 ? lines.take(12).toList() : lines;
    final truncated = visibleLines.length < lines.length;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('file-change-hover-preview'),
        width: width,
        height: height,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 17,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.trace,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '+${stats.additions}',
                    style: TextStyle(color: palette.ack),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-${stats.deletions}',
                    style: TextStyle(color: palette.fault),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            if (diff.trim().isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: _MutedText('App Server 未提供可显示的 Diff。'),
              )
            else
              Flexible(
                child: Container(
                  color: palette.field,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText.rich(
                        TextSpan(
                          children: _previewSpans(palette, visibleLines),
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Text(
                  '仅显示前 12 行 · 打开“审核”查看完整 Diff',
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _previewSpans(
    YeknomPalette palette,
    List<_DiffPreviewLine> lines,
  ) {
    return [
      for (var index = 0; index < lines.length; index++)
        TextSpan(
          text:
              '${lines[index].lineNumber?.toString().padLeft(4) ?? '    '}  '
              '${lines[index].text}\n',
          style: TextStyle(
            color: _lineColor(palette, lines[index].text),
            backgroundColor: _lineBackground(palette, lines[index].text),
          ),
        ),
    ];
  }

  Color _lineColor(YeknomPalette palette, String line) {
    return switch (line) {
      _ when line.startsWith('+++') || line.startsWith('---') => palette.muted,
      _ when line.startsWith('+') => palette.ack,
      _ when line.startsWith('-') => palette.fault,
      _ when line.startsWith('@@') => palette.active,
      _ => palette.trace,
    };
  }

  Color? _lineBackground(YeknomPalette palette, String line) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return palette.ack.withValues(alpha: 0.12);
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return palette.fault.withValues(alpha: 0.12);
    }
    return null;
  }
}

class _CodeReviewDialog extends StatefulWidget {
  const _CodeReviewDialog({required this.changes, required this.turnDiff});

  final List<CodexFileChange> changes;
  final String? turnDiff;

  @override
  State<_CodeReviewDialog> createState() => _CodeReviewDialogState();
}

class _CodeReviewDialogState extends State<_CodeReviewDialog> {
  int _selectedIndex = 0;

  List<CodexFileChange> get _targets {
    if (widget.changes.isNotEmpty) {
      final fallback = widget.turnDiff;
      final hasMissingDiff = widget.changes.any(
        (change) => change.diff.trim().isEmpty,
      );
      if (hasMissingDiff && fallback != null && fallback.isNotEmpty) {
        return [
          ...widget.changes,
          CodexFileChange(path: '本次任务完整 Diff', kind: '任务', diff: fallback),
        ];
      }
      return widget.changes;
    }
    final diff = widget.turnDiff;
    if (diff == null || diff.isEmpty) return const [];
    return [CodexFileChange(path: '本次任务完整 Diff', kind: '任务', diff: diff)];
  }

  _DiffStats get _stats {
    final fallback = widget.turnDiff;
    final hasMissingDiff = widget.changes.any(
      (change) => change.diff.trim().isEmpty,
    );
    if (hasMissingDiff && fallback != null && fallback.isNotEmpty) {
      return _diffStats(fallback);
    }
    return _targets.fold(
      const _DiffStats(0, 0),
      (total, change) => total + _diffStats(change.diff),
    );
  }

  bool get _statsUnknown =>
      widget.changes.any((change) => change.diff.trim().isEmpty) &&
      (widget.turnDiff == null || widget.turnDiff!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final targets = _targets;
    final selected = targets.isEmpty
        ? null
        : targets[_selectedIndex.clamp(0, targets.length - 1)];
    final stats = _stats;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('code-review-dialog'),
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: palette.bench,
      child: SizedBox(
        width: (size.width - 24).clamp(680.0, 1240.0).toDouble(),
        height: (size.height - 24).clamp(480.0, 820.0).toDouble(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              child: Row(
                children: [
                  Icon(Icons.edit_note_outlined, color: palette.muted),
                  const SizedBox(width: 10),
                  Text('审查', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭审查',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  _ReviewFilter(label: '所有仓库', icon: Icons.expand_more),
                  const SizedBox(width: 18),
                  _ReviewFilter(label: '上一轮', icon: Icons.expand_more),
                  const SizedBox(width: 18),
                  Text(
                    _diffCountLabel(
                      '+',
                      stats.additions,
                      unknown: _statsUnknown,
                    ),
                    style: TextStyle(color: palette.ack),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _diffCountLabel(
                      '-',
                      stats.deletions,
                      unknown: _statsUnknown,
                    ),
                    style: TextStyle(color: palette.fault),
                  ),
                  const Spacer(),
                  Text(
                    widget.changes.isEmpty
                        ? '完整 Diff'
                        : '${widget.changes.length} 个文件',
                    style: TextStyle(color: palette.muted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            Expanded(
              child: targets.isEmpty
                  ? const Center(child: Text('当前任务没有可审查的文件变更。'))
                  : Row(
                      children: [
                        SizedBox(
                          width: 320,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: targets.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: palette.border),
                            itemBuilder: (context, index) {
                              final target = targets[index];
                              final targetStats = _diffStats(target.diff);
                              return ListTile(
                                selected: index == _selectedIndex,
                                selectedTileColor: palette.selected,
                                dense: true,
                                leading: Icon(
                                  Icons.description_outlined,
                                  size: 18,
                                  color: index == _selectedIndex
                                      ? palette.ack
                                      : palette.muted,
                                ),
                                title: Text(
                                  target.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  target.diff.trim().isEmpty
                                      ? 'Diff unavailable'
                                      : '${targetStats.additions} additions · ${targetStats.deletions} deletions',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () =>
                                    setState(() => _selectedIndex = index),
                              );
                            },
                          ),
                        ),
                        VerticalDivider(width: 1, color: palette.border),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: selected == null
                                ? const SizedBox.shrink()
                                : _ReviewDiffViewer(change: selected),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewFilter extends StatelessWidget {
  const _ReviewFilter({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: palette.trace)),
        const SizedBox(width: 4),
        Icon(icon, size: 18, color: palette.muted),
      ],
    );
  }
}

class _ReviewDiffViewer extends StatelessWidget {
  const _ReviewDiffViewer({required this.change});

  final CodexFileChange change;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _diffStats(change.diff);
    final unknown = change.diff.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: palette.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                change.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              _diffCountLabel('+', stats.additions, unknown: unknown),
              style: TextStyle(color: palette.ack),
            ),
            const SizedBox(width: 8),
            Text(
              _diffCountLabel('-', stats.deletions, unknown: unknown),
              style: TextStyle(color: palette.fault),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: change.diff.isEmpty
                ? const Center(child: Text('没有可显示的 Diff。'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText.rich(
                        TextSpan(children: _diffSpans(palette, change.diff)),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  List<TextSpan> _diffSpans(YeknomPalette palette, String value) {
    return value
        .split('\n')
        .map((line) {
          final color = switch (line) {
            _ when line.startsWith('+++') || line.startsWith('---') =>
              palette.muted,
            _ when line.startsWith('+') => palette.ack,
            _ when line.startsWith('-') => palette.fault,
            _ when line.startsWith('@@') => palette.active,
            _ => palette.trace,
          };
          return TextSpan(
            text: '$line\n',
            style: TextStyle(color: color),
          );
        })
        .toList(growable: false);
  }
}

class _TaskPlanPanel extends StatefulWidget {
  const _TaskPlanPanel({required this.plan});

  final TaskPlan plan;

  /// 创建负责当前步骤自动聚焦的面板状态。
  /// Creates panel state that automatically focuses the current step.
  @override
  State<_TaskPlanPanel> createState() => _TaskPlanPanelState();
}

class _TaskPlanPanelState extends State<_TaskPlanPanel> {
  late List<GlobalKey> _stepKeys;

  TaskPlan get plan => widget.plan;

  /// 初始化步骤锚点，并在首帧把当前步骤滚入可见区域。
  /// Initializes step anchors and scrolls the current step into view after the first frame.
  @override
  void initState() {
    super.initState();
    _stepKeys = List.generate(plan.steps.length, (_) => GlobalKey());
    _scheduleFocusedStepVisibility();
  }

  /// 在计划长度或当前步骤变化后同步锚点并重新聚焦。
  /// Synchronizes anchors and refocuses after the plan length or current step changes.
  @override
  void didUpdateWidget(covariant _TaskPlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_stepKeys.length != plan.steps.length) {
      _stepKeys = List.generate(plan.steps.length, (_) => GlobalKey());
    }
    if (oldWidget.plan.focusedStepIndex != plan.focusedStepIndex ||
        oldWidget.plan.steps.length != plan.steps.length) {
      _scheduleFocusedStepVisibility();
    }
  }

  /// 等待布局完成后，将当前步骤平滑滚动到步骤列表的中央可见区域。
  /// Waits for layout, then smoothly scrolls the current step into the center of the visible list.
  void _scheduleFocusedStepVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = plan.focusedStepIndex;
      if (index < 0 || index >= _stepKeys.length) return;
      final stepContext = _stepKeys[index].currentContext;
      if (stepContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          stepContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// 构建运行中任务的悬浮分步进度面板与当前步骤指示。
  /// Builds the floating step-progress panel and current-step indicator for a running task.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final focusedIndex = plan.focusedStepIndex;
    final currentStep = focusedIndex < 0 ? 0 : focusedIndex + 1;
    return Semantics(
      container: true,
      label: '执行计划，共 ${plan.steps.length} 步，当前第 $currentStep 步',
      child: Column(
        key: const Key('task-plan-progress'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 17,
                          color: palette.active,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            plan.explanation ?? '执行计划',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: palette.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${plan.completedStepCount}/${plan.steps.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: palette.border),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          plan.steps.length,
                          (index) => KeyedSubtree(
                            key: _stepKeys[index],
                            child: _TaskPlanStepRow(
                              key: Key('task-plan-step-$index'),
                              step: plan.steps[index],
                              focused: index == focusedIndex,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('task-plan-current-step'),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TaskPlanStatusMark(
                  status: focusedIndex < 0
                      ? TaskPlanStepStatus.pending
                      : plan.steps[focusedIndex].status,
                  active: true,
                ),
                const SizedBox(width: 7),
                Text(
                  '第 $currentStep / ${plan.steps.length} 步',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPlanStepRow extends StatelessWidget {
  const _TaskPlanStepRow({
    required this.step,
    required this.focused,
    super.key,
  });

  final TaskPlanStep step;
  final bool focused;

  /// 构建单条计划步骤，并以文字语义和图形共同表达状态。
  /// Builds one plan step, expressing status through both semantics and visuals.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final statusLabel = switch (step.status) {
      TaskPlanStepStatus.pending => '待执行',
      TaskPlanStepStatus.inProgress => '进行中',
      TaskPlanStepStatus.completed => '已完成',
    };
    return Semantics(
      label: '$statusLabel：${step.step}',
      child: Container(
        color: focused
            ? palette.active.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _TaskPlanStatusMark(status: step.status, active: focused),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                step.step,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: step.status == TaskPlanStepStatus.completed
                      ? palette.muted
                      : palette.trace,
                  fontWeight: focused ? FontWeight.w600 : FontWeight.w400,
                  decoration: step.status == TaskPlanStepStatus.completed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskPlanStatusMark extends StatelessWidget {
  const _TaskPlanStatusMark({required this.status, required this.active});

  final TaskPlanStepStatus status;
  final bool active;

  /// 构建静态状态标记，避免持续动画干扰阅读和 Widget 测试稳定性。
  /// Builds a static status mark to avoid perpetual motion and unstable widget tests.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (status == TaskPlanStepStatus.completed) {
      return Icon(Icons.check_circle, size: 16, color: palette.ack);
    }
    final color = active ? palette.active : palette.muted;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: active ? 2 : 1.5),
      ),
      alignment: Alignment.center,
      child: status == TaskPlanStepStatus.inProgress
          ? Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
          : null,
    );
  }
}

/// 输入框右下角的新任务模型与推理强度双拨盘。
/// A paired new-task model and reasoning-effort control in the composer's lower-right corner.
class _ComposerModelControls extends StatelessWidget {
  const _ComposerModelControls({
    required this.controller,
    required this.compact,
  });

  final CodexController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final modelEnabled = controller.canSelectModel;
    final effortEnabled = controller.canSelectReasoningEffort;
    final selectionError = controller.modelSelectionError;
    final contentColor = selectionError != null
        ? palette.fault
        : modelEnabled
        ? palette.trace
        : palette.muted;
    final modelWidth = compact ? 88.0 : 152.0;
    final effortWidth = compact ? 58.0 : 76.0;
    return Container(
      key: const Key('composer-model-controls'),
      height: 34,
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            key: const Key('model-selector'),
            enabled: modelEnabled,
            padding: EdgeInsets.zero,
            tooltip:
                selectionError ?? '切换后续新任务的模型：${controller.selectedModelLabel}',
            onSelected: (value) {
              unawaited(controller.setModel(value.isEmpty ? null : value));
            },
            itemBuilder: (context) => [
              if (selectionError != null)
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(selectionError),
                ),
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('仅影响后续新任务'),
              ),
              CheckedPopupMenuItem(
                key: const Key('model-option-follow-config'),
                value: '',
                checked: controller.selectedModelId == null,
                child: Text('跟随 Codex 配置 · ${controller.configuredModelLabel}'),
              ),
              ...controller.modelOptions.map(
                (option) => CheckedPopupMenuItem(
                  key: ValueKey('model-option-${option.id}'),
                  value: option.id,
                  checked: controller.selectedModelId == option.id,
                  child: Text(
                    '新任务模型：${option.displayName}${option.displayName == option.id ? '' : ' · ${option.id}'}',
                  ),
                ),
              ),
            ],
            child: SizedBox(
              width: modelWidth,
              height: 32,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 5),
                child: Row(
                  children: [
                    Icon(
                      selectionError == null
                          ? Icons.smart_toy_outlined
                          : Icons.error_outline,
                      size: 15,
                      color: contentColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        controller.newTaskModelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: contentColor),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 15, color: palette.muted),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<ReasoningEffort>(
            key: const Key('reasoning-effort-selector'),
            enabled: effortEnabled,
            padding: EdgeInsets.zero,
            tooltip:
                selectionError ??
                '切换后续新任务的推理强度：${controller.reasoningEffort.label}',
            onSelected: (value) {
              unawaited(controller.setReasoningEffort(value));
            },
            itemBuilder: (context) => controller.reasoningEffortOptions
                .map(
                  (effort) => CheckedPopupMenuItem(
                    key: ValueKey('reasoning-option-${effort.name}'),
                    value: effort,
                    checked: controller.reasoningEffort == effort,
                    child: Text(effort.label),
                  ),
                )
                .toList(growable: false),
            child: SizedBox(
              width: effortWidth,
              height: 32,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        controller.reasoningEffort.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: contentColor),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 15, color: palette.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerActivityPill extends StatelessWidget {
  const _ComposerActivityPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      key: const Key('composer-activity-pill'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? palette.active : palette.muted,
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ],
      ),
    );
  }
}

class _ComposerFileChangePill extends StatelessWidget {
  const _ComposerFileChangePill({
    required this.changes,
    required this.turnDiff,
  });

  final List<CodexFileChange> changes;
  final String? turnDiff;

  _DiffStats get _stats {
    final stats = changes.fold(
      const _DiffStats(0, 0),
      (total, change) => total + _diffStats(change.diff),
    );
    final fallback = turnDiff;
    final hasMissingDiff = changes.any((change) => change.diff.trim().isEmpty);
    return hasMissingDiff && fallback != null && fallback.isNotEmpty
        ? _diffStats(fallback)
        : stats;
  }

  bool get _statsUnknown =>
      changes.any((change) => change.diff.trim().isEmpty) &&
      (turnDiff == null || turnDiff!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _stats;
    return Container(
      key: const Key('composer-file-change-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${changes.length} 个文件已更改',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
          const SizedBox(width: 9),
          Text(
            _diffCountLabel('+', stats.additions, unknown: _statsUnknown),
            style: TextStyle(color: palette.ack),
          ),
          const SizedBox(width: 8),
          Text(
            _diffCountLabel('-', stats.deletions, unknown: _statsUnknown),
            style: TextStyle(color: palette.fault),
          ),
        ],
      ),
    );
  }
}

class _ComposerPanel extends StatefulWidget {
  const _ComposerPanel({
    super.key,
    required this.controller,
    required this.composer,
    required this.onSend,
    required this.onSteer,
  });

  final CodexController controller;
  final TextEditingController composer;
  final Future<bool> Function(_ComposerSubmission submission) onSend;
  final Future<bool> Function(_ComposerSubmission submission) onSteer;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
  static const _clipboardFileReader = ClipboardFileReader();
  final List<_ComposerAttachment> _attachments = [];
  final Set<String> _selectedSkillPaths = {};
  final Map<String, Uint8List> _securityBookmarks = {};
  final Set<String> _temporaryAttachmentPaths = {};
  late RuntimeStatus _lastRuntimeStatus;
  bool _draggingFiles = false;
  bool _includeWorkspace = false;
  bool _planMode = false;
  bool _recordSkill = false;
  String? _goal;

  CodexController get controller => widget.controller;
  TextEditingController get composer => widget.composer;

  int get _fileChangeCount => controller.entries
      .where((entry) => entry.title == '文件变更')
      .fold(0, (total, entry) => total + entry.detail.split('\n').length);

  List<CodexSkill> get _selectedSkills => controller.skills
      .where((skill) => _selectedSkillPaths.contains(skill.path))
      .toList(growable: false);

  bool get _hasComposerContext =>
      _attachments.isNotEmpty ||
      _includeWorkspace ||
      _goal?.isNotEmpty == true ||
      _planMode ||
      _recordSkill ||
      _selectedSkillPaths.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _lastRuntimeStatus = controller.status;
    controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _ComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _lastRuntimeStatus = controller.status;
    controller.addListener(_handleControllerChanged);
    _releaseDetachedAttachmentResources();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _releaseAllAttachmentResources();
    super.dispose();
  }

  void _handleControllerChanged() {
    final status = controller.status;
    final turnEnded =
        _lastRuntimeStatus == RuntimeStatus.running &&
        status != RuntimeStatus.running;
    _lastRuntimeStatus = status;
    if (turnEnded) _releaseDetachedAttachmentResources();
  }

  void _releaseDetachedAttachmentResources() {
    final attachedPaths = _attachments
        .map((attachment) => attachment.path)
        .toSet();
    final timelineImagePaths = controller.entries
        .expand((entry) => entry.imagePaths)
        .toSet();
    final paths =
        <String>{..._securityBookmarks.keys, ..._temporaryAttachmentPaths}
            .where(
              (path) =>
                  !attachedPaths.contains(path) &&
                  !timelineImagePaths.contains(path),
            )
            .toList(growable: false);
    for (final path in paths) {
      _releaseAttachmentResources(path);
    }
  }

  void _releaseAllAttachmentResources() {
    final paths = <String>{
      ..._securityBookmarks.keys,
      ..._temporaryAttachmentPaths,
    };
    for (final path in paths) {
      _releaseAttachmentResources(path);
    }
  }

  void _releaseAttachmentResources(String path) {
    _releaseSecurityBookmark(path);
    if (_temporaryAttachmentPaths.remove(path)) {
      unawaited(_clipboardFileReader.deleteTemporaryItem(path));
    }
  }

  void _releaseSecurityBookmark(String path) {
    final bookmark = _securityBookmarks.remove(path);
    if (bookmark != null) unawaited(_stopAccessingBookmark(bookmark));
  }

  Future<void> _stopAccessingBookmark(Uint8List bookmark) async {
    try {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    } on MissingPluginException {
      // The host platform does not require macOS security-scoped access.
    } on PlatformException {
      // The resource is already unavailable; there is nothing else to release.
    }
  }

  String get _activityLabel {
    if (controller.status == RuntimeStatus.running) {
      final count = _fileChangeCount;
      return count == 0 ? '正在处理任务' : '正在处理 · $count 个文件已变更';
    }
    return controller.status == RuntimeStatus.ready ? '任务已就绪' : '等待运行时连接';
  }

  Future<void> _submit() async {
    final submission = _ComposerSubmission(
      attachments: List.unmodifiable(_attachments),
      includeWorkspace: _includeWorkspace,
      goal: _goal,
      planMode: _planMode,
      recordSkill: _recordSkill,
      skills: _selectedSkills,
    );
    final submitted = controller.canSteer
        ? await widget.onSteer(submission)
        : await widget.onSend(submission);
    if (!submitted || !mounted) return;
    setState(() {
      composer.clear();
      _attachments.clear();
      _selectedSkillPaths.clear();
      _includeWorkspace = false;
      _recordSkill = false;
    });
    if (controller.status != RuntimeStatus.running) {
      _releaseDetachedAttachmentResources();
    }
  }

  Future<void> _handleAddAction(_AddMenuAction action) async {
    switch (action.kind) {
      case _AddMenuActionKind.files:
        await _showAttachmentPicker();
      case _AddMenuActionKind.workspace:
        setState(() => _includeWorkspace = !_includeWorkspace);
      case _AddMenuActionKind.goal:
        await _editGoal();
      case _AddMenuActionKind.plan:
        setState(() => _planMode = !_planMode);
      case _AddMenuActionKind.recordSkill:
        setState(() => _recordSkill = !_recordSkill);
      case _AddMenuActionKind.skill:
        final path = action.value;
        if (path == null) return;
        setState(() {
          if (!_selectedSkillPaths.add(path)) {
            _selectedSkillPaths.remove(path);
          }
        });
    }
  }

  Future<void> _showAttachmentPicker() async {
    final choice = await showDialog<_AttachmentPickerKind>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('attachment-picker-dialog'),
        title: const Text('文件和文件夹'),
        content: const Text('选择要随下一条消息发送的文件，或添加一个文件夹路径作为任务上下文。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          OutlinedButton.icon(
            key: const Key('pick-folder-button'),
            onPressed: () =>
                Navigator.pop(dialogContext, _AttachmentPickerKind.folder),
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: const Text('文件夹'),
          ),
          FilledButton.icon(
            key: const Key('pick-files-button'),
            onPressed: () =>
                Navigator.pop(dialogContext, _AttachmentPickerKind.files),
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('文件'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final attachments = switch (choice) {
        _AttachmentPickerKind.files =>
          (await openFiles(confirmButtonText: '附加文件'))
              .map(
                (file) =>
                    _ComposerAttachment(path: file.path, isDirectory: false),
              )
              .toList(growable: false),
        _AttachmentPickerKind.folder => [
          if (await getDirectoryPath(confirmButtonText: '附加文件夹')
              case final path?)
            _ComposerAttachment(path: path, isDirectory: true),
        ],
      };
      if (!mounted || attachments.isEmpty) return;
      _addAttachments(attachments);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开文件选择器。')));
    }
  }

  Future<void> _pasteFromClipboard() async {
    final items = await _clipboardFileReader.readItems();
    if (!mounted) return;
    if (items.isNotEmpty) {
      if (!controller.canSend && !controller.canSteer) {
        return;
      }
      _addAttachments(
        items.map(
          (item) => _ComposerAttachment(
            path: item.path,
            isDirectory: item.isDirectory,
            isTemporary: item.isTemporary,
          ),
        ),
      );
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pastedText = data?.text;
    if (!mounted || pastedText == null || pastedText.isEmpty) return;
    final current = composer.text;
    final selection = composer.selection;
    final rawStart = selection.isValid ? selection.start : current.length;
    final rawEnd = selection.isValid ? selection.end : current.length;
    final start = rawStart.clamp(0, current.length);
    final end = rawEnd.clamp(0, current.length);
    final lower = start < end ? start : end;
    final upper = start < end ? end : start;
    composer.value = TextEditingValue(
      text: current.replaceRange(lower, upper, pastedText),
      selection: TextSelection.collapsed(offset: lower + pastedText.length),
    );
  }

  Widget _buildComposerContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    void paste() {
      editableTextState.hideToolbar();
      unawaited(_pasteFromClipboard());
    }

    var hasPaste = false;
    final items = editableTextState.contextMenuButtonItems
        .map((item) {
          if (item.type != ContextMenuButtonType.paste) return item;
          hasPaste = true;
          return item.copyWith(onPressed: paste);
        })
        .toList(growable: true);
    if (!hasPaste) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: paste,
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  Future<void> _handleDroppedFiles(List<DropItem> items) async {
    if (items.isEmpty ||
        !mounted ||
        (!controller.canSend && !controller.canSteer)) {
      return;
    }
    final attachments = <_ComposerAttachment>[];
    for (final item in items) {
      final path = item.path;
      if (path.isEmpty) continue;
      if (item.extraAppleBookmark case final bookmark?
          when bookmark.isNotEmpty && !_securityBookmarks.containsKey(path)) {
        var accessStarted = false;
        try {
          accessStarted = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
        } on MissingPluginException {
          // The host platform does not require macOS security-scoped access.
        } on PlatformException {
          // Keep the attachment usable on unsandboxed hosts when scope setup fails.
        }
        if (!mounted) {
          if (accessStarted) await _stopAccessingBookmark(bookmark);
          return;
        }
        if (accessStarted) _securityBookmarks[path] = bookmark;
      }
      attachments.add(
        _ComposerAttachment(path: path, isDirectory: item is DropItemDirectory),
      );
    }
    if (!mounted || attachments.isEmpty) return;
    _addAttachments(attachments);
  }

  void _addAttachments(Iterable<_ComposerAttachment> attachments) {
    if (!controller.canSend && !controller.canSteer) return;
    setState(() {
      for (final attachment in attachments) {
        if (attachment.path.isEmpty) continue;
        if (attachment.isTemporary) {
          _temporaryAttachmentPaths.add(attachment.path);
        }
        final index = _attachments.indexWhere(
          (existing) => existing.path == attachment.path,
        );
        if (index < 0) {
          _attachments.add(attachment);
        } else {
          final existing = _attachments[index];
          _attachments[index] = _ComposerAttachment(
            path: attachment.path,
            isDirectory: existing.isDirectory || attachment.isDirectory,
            isTemporary: existing.isTemporary || attachment.isTemporary,
          );
        }
      }
    });
  }

  void _removeAttachment(String path) {
    _releaseAttachmentResources(path);
    setState(() => _attachments.removeWhere((item) => item.path == path));
  }

  Future<void> _showImagePreview(String path) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        key: const Key('composer-image-preview-dialog'),
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.file(
                File(path),
                key: const Key('composer-image-preview'),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox(
                  width: 420,
                  height: 260,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 56,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: '关闭预览',
                color: Colors.white,
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editGoal() async {
    var draft = _goal ?? '';
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('composer-goal-dialog'),
        title: const Text('设置目标'),
        content: SizedBox(
          width: 480,
          child: TextFormField(
            key: const Key('composer-goal-field'),
            initialValue: draft,
            onChanged: (value) => draft = value,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: '描述这个任务需要持续追求的结果'),
          ),
        ),
        actions: [
          if (_goal?.isNotEmpty == true)
            TextButton(
              key: const Key('clear-composer-goal'),
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('清除'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('save-composer-goal'),
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const Text('设置'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _goal = result.isEmpty ? null : result);
  }

  List<PopupMenuEntry<_AddMenuAction>> _buildAddMenu(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final workspace = controller.workspacePath;
    final workspaceName = workspace == null ? '当前项目' : _pathLabel(workspace);
    final entries = <PopupMenuEntry<_AddMenuAction>>[
      _AddMenuHeader(label: '添加', palette: palette),
      _AddMenuItem(
        key: const Key('add-files-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.files),
        icon: Icons.attach_file,
        label: '文件和文件夹',
        selected: _attachments.isNotEmpty,
      ),
      _AddMenuItem(
        key: const Key('add-workspace-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.workspace),
        icon: Icons.terminal_outlined,
        label: '附加 $workspaceName',
        selected: _includeWorkspace,
        enabled: workspace != null,
      ),
      _AddMenuItem(
        key: const Key('add-goal-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.goal),
        icon: Icons.track_changes_outlined,
        label: '目标',
        description: _goal ?? '设置要持续追求的目标',
        selected: _goal?.isNotEmpty == true,
      ),
      _AddMenuItem(
        key: const Key('add-plan-mode-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.plan),
        icon: Icons.lightbulb_outline,
        label: '计划模式',
        description: _planMode ? '已开启计划模式' : '开启计划模式',
        selected: _planMode,
      ),
      _AddMenuItem(
        key: const Key('record-skill-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.recordSkill),
        icon: Icons.radio_button_checked,
        label: '录制技能',
        description: _recordSkill ? '将本次流程整理为技能' : null,
        selected: _recordSkill,
      ),
      _AddMenuHeader(label: '插件', palette: palette),
    ];
    if (controller.skillsLoading && controller.skills.isEmpty) {
      entries.add(
        _AddMenuMessage(
          key: Key('composer-skills-loading'),
          label: '正在读取可用技能…',
        ),
      );
    } else if (controller.skills.isEmpty) {
      entries.add(
        _AddMenuMessage(
          key: const Key('composer-skills-empty'),
          label: controller.skillsError ?? '当前项目没有可用技能',
        ),
      );
    } else {
      for (final skill in controller.skills) {
        entries.add(
          _AddMenuItem(
            key: ValueKey('composer-skill-${skill.name}'),
            value: _AddMenuAction(_AddMenuActionKind.skill, skill.path),
            icon: _skillIcon(skill.name),
            label: skill.label,
            description: skill.summary,
            selected: _selectedSkillPaths.contains(skill.path),
          ),
        );
      }
    }
    return entries;
  }

  IconData _skillIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.contains('sheet') || lower.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (lower.contains('presentation') || lower.contains('slide')) {
      return Icons.slideshow_outlined;
    }
    if (lower.contains('document') || lower.contains('doc')) {
      return Icons.description_outlined;
    }
    return Icons.auto_awesome_outlined;
  }

  String _pathLabel(String path) {
    final segments = path
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? path : segments.last;
  }

  /// 构建支持 Enter 发送、Shift+Enter 换行的任务输入面板。
  /// Builds the task composer that sends with Enter and inserts lines with Shift+Enter.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.fileChanges.isEmpty &&
              (controller.activeThreadId != null ||
                  controller.status == RuntimeStatus.running))
            _ComposerActivityPill(
              label: _activityLabel,
              active: controller.status == RuntimeStatus.running,
            ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              DropTarget(
                onDragEntered: (_) {
                  if ((controller.canSend || controller.canSteer) && mounted) {
                    setState(() => _draggingFiles = true);
                  }
                },
                onDragExited: (_) {
                  if (mounted) setState(() => _draggingFiles = false);
                },
                onDragDone: (details) {
                  if (mounted) setState(() => _draggingFiles = false);
                  if (!controller.canSend && !controller.canSteer) return;
                  unawaited(_handleDroppedFiles(details.files));
                },
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      constraints: const BoxConstraints(minHeight: 126),
                      padding: const EdgeInsets.fromLTRB(16, 13, 12, 10),
                      decoration: BoxDecoration(
                        color: _draggingFiles
                            ? Color.alphaBlend(
                                palette.active.withValues(alpha: 0.08),
                                palette.field,
                              )
                            : palette.field,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _draggingFiles
                              ? palette.active
                              : palette.controlBorder,
                          width: _draggingFiles ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 64,
                              maxHeight: 124,
                            ),
                            child: CallbackShortcuts(
                              bindings: {
                                const SingleActivator(
                                  LogicalKeyboardKey.enter,
                                ): () {
                                  unawaited(_submit());
                                },
                                const SingleActivator(
                                  LogicalKeyboardKey.keyV,
                                  meta: true,
                                ): () {
                                  unawaited(_pasteFromClipboard());
                                },
                                const SingleActivator(
                                  LogicalKeyboardKey.keyV,
                                  control: true,
                                ): () {
                                  unawaited(_pasteFromClipboard());
                                },
                              },
                              child: TextField(
                                key: const Key('composer-field'),
                                controller: composer,
                                enabled:
                                    controller.canSend || controller.canSteer,
                                contextMenuBuilder: _buildComposerContextMenu,
                                minLines: 2,
                                maxLines: 5,
                                textInputAction: TextInputAction.newline,
                                style: TextStyle(color: palette.trace),
                                decoration: InputDecoration(
                                  hintText: '随心输入',
                                  hintStyle: TextStyle(color: palette.muted),
                                  filled: false,
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_hasComposerContext) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  for (final attachment in _attachments)
                                    _ComposerContextChip(
                                      key: ValueKey(
                                        'composer-attachment-${attachment.path}',
                                      ),
                                      icon:
                                          !attachment.isDirectory &&
                                              _isImagePath(attachment.path)
                                          ? Icons.image_outlined
                                          : Icons.attach_file,
                                      thumbnailPath:
                                          !attachment.isDirectory &&
                                              _isImagePath(attachment.path)
                                          ? attachment.path
                                          : null,
                                      label: _pathLabel(attachment.path),
                                      onRemove: () =>
                                          _removeAttachment(attachment.path),
                                      onPreview:
                                          !attachment.isDirectory &&
                                              _isImagePath(attachment.path)
                                          ? () => _showImagePreview(
                                              attachment.path,
                                            )
                                          : null,
                                    ),
                                  if (_includeWorkspace)
                                    _ComposerContextChip(
                                      key: const Key('composer-workspace-chip'),
                                      icon: Icons.terminal_outlined,
                                      label: controller.workspacePath == null
                                          ? '当前项目'
                                          : _pathLabel(
                                              controller.workspacePath!,
                                            ),
                                      onRemove: () => setState(
                                        () => _includeWorkspace = false,
                                      ),
                                    ),
                                  if (_goal case final goal?)
                                    _ComposerContextChip(
                                      key: const Key('composer-goal-chip'),
                                      icon: Icons.track_changes_outlined,
                                      label: goal,
                                      onRemove: () =>
                                          setState(() => _goal = null),
                                    ),
                                  if (_planMode)
                                    _ComposerContextChip(
                                      key: const Key('composer-plan-mode-chip'),
                                      icon: Icons.lightbulb_outline,
                                      label: '计划模式',
                                      onRemove: () =>
                                          setState(() => _planMode = false),
                                    ),
                                  if (_recordSkill)
                                    _ComposerContextChip(
                                      key: const Key(
                                        'composer-record-skill-chip',
                                      ),
                                      icon: Icons.radio_button_checked,
                                      label: '录制技能',
                                      onRemove: () =>
                                          setState(() => _recordSkill = false),
                                    ),
                                  for (final skill in _selectedSkills)
                                    _ComposerContextChip(
                                      key: ValueKey(
                                        'composer-skill-chip-${skill.name}',
                                      ),
                                      icon: _skillIcon(skill.name),
                                      label: skill.label,
                                      onRemove: () => setState(
                                        () => _selectedSkillPaths.remove(
                                          skill.path,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 9),
                          ],
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final showAttachment =
                                  constraints.maxWidth >= 420;
                              final showApproval = constraints.maxWidth >= 340;
                              final showApprovalLabel =
                                  constraints.maxWidth >= 460;
                              final showModel = constraints.maxWidth >= 240;
                              return Row(
                                children: [
                                  if (showAttachment)
                                    PopupMenuButton<_AddMenuAction>(
                                      key: const Key('composer-add-button'),
                                      enabled:
                                          controller.canSend ||
                                          controller.canSteer,
                                      tooltip: '添加上下文',
                                      icon: const Icon(Icons.add, size: 20),
                                      constraints: const BoxConstraints(
                                        minWidth: 390,
                                        maxWidth: 470,
                                        maxHeight: 620,
                                      ),
                                      color: palette.field,
                                      surfaceTintColor: Colors.transparent,
                                      elevation: 10,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        side: BorderSide(
                                          color: palette.controlBorder,
                                        ),
                                      ),
                                      menuPadding: const EdgeInsets.fromLTRB(
                                        8,
                                        8,
                                        8,
                                        10,
                                      ),
                                      onOpened: () {
                                        if (controller.skills.isEmpty &&
                                            !controller.skillsLoading) {
                                          unawaited(controller.refreshSkills());
                                        }
                                      },
                                      onSelected: (action) =>
                                          unawaited(_handleAddAction(action)),
                                      itemBuilder: _buildAddMenu,
                                    ),
                                  if (showApproval)
                                    PopupMenuButton<ApprovalMode>(
                                      tooltip:
                                          '审批模式：${controller.approvalMode.label}',
                                      onSelected: controller.setApprovalMode,
                                      itemBuilder: (context) => ApprovalMode
                                          .values
                                          .map(
                                            (mode) => CheckedPopupMenuItem(
                                              value: mode,
                                              checked:
                                                  controller.approvalMode ==
                                                  mode,
                                              child: Text(mode.label),
                                            ),
                                          )
                                          .toList(growable: false),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.verified_user_outlined,
                                              size: 16,
                                            ),
                                            if (showApprovalLabel) ...[
                                              const SizedBox(width: 5),
                                              Text(
                                                controller.approvalMode.label,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  if (showModel) ...[
                                    _ComposerModelControls(
                                      controller: controller,
                                      compact: constraints.maxWidth < 430,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (controller.canStop)
                                    IconButton.filled(
                                      tooltip: '停止当前任务',
                                      onPressed: controller.stopCurrentTurn,
                                      style: IconButton.styleFrom(
                                        backgroundColor: scheme.primary,
                                        foregroundColor: scheme.onPrimary,
                                      ),
                                      icon: const Icon(Icons.stop, size: 19),
                                    )
                                  else
                                    IconButton.filled(
                                      tooltip: '发送任务',
                                      onPressed: controller.canSend
                                          ? _submit
                                          : null,
                                      style: IconButton.styleFrom(
                                        backgroundColor: scheme.primary,
                                        foregroundColor: scheme.onPrimary,
                                      ),
                                      icon: const Icon(
                                        Icons.arrow_upward,
                                        size: 19,
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_draggingFiles)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Semantics(
                            key: const Key('composer-drop-overlay'),
                            liveRegion: true,
                            label: '松开即可添加文件',
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.active.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.raised,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: palette.active.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.18,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.file_upload_outlined,
                                        size: 20,
                                        color: palette.active,
                                      ),
                                      const SizedBox(width: 9),
                                      Text(
                                        '松开即可添加文件',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: palette.trace,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (controller.fileChanges.isNotEmpty)
                Positioned(
                  key: const Key('composer-file-change-overlay'),
                  top: -18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _ComposerFileChangePill(
                      changes: controller.fileChanges,
                      turnDiff: controller.turnDiff,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _AttachmentPickerKind { files, folder }

enum _AddMenuActionKind { files, workspace, goal, plan, recordSkill, skill }

class _AddMenuAction {
  const _AddMenuAction(this.kind, [this.value]);

  final _AddMenuActionKind kind;
  final String? value;
}

class _ComposerAttachment {
  const _ComposerAttachment({
    required this.path,
    required this.isDirectory,
    this.isTemporary = false,
  });

  final String path;
  final bool isDirectory;
  final bool isTemporary;
}

class _ComposerSubmission {
  const _ComposerSubmission({
    required this.attachments,
    required this.includeWorkspace,
    required this.goal,
    required this.planMode,
    required this.recordSkill,
    required this.skills,
  });

  final List<_ComposerAttachment> attachments;
  final bool includeWorkspace;
  final String? goal;
  final bool planMode;
  final bool recordSkill;
  final List<CodexSkill> skills;

  bool get hasContext =>
      attachments.isNotEmpty ||
      includeWorkspace ||
      goal?.isNotEmpty == true ||
      planMode ||
      recordSkill ||
      skills.isNotEmpty;
}

class _AddMenuHeader extends PopupMenuEntry<_AddMenuAction> {
  const _AddMenuHeader({required this.label, required this.palette});

  final String label;
  final YeknomPalette palette;

  @override
  double get height => 34;

  @override
  bool represents(_AddMenuAction? value) => false;

  @override
  State<_AddMenuHeader> createState() => _AddMenuHeaderState();
}

class _AddMenuHeaderState extends State<_AddMenuHeader> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        widget.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: widget.palette.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _AddMenuItem extends PopupMenuItem<_AddMenuAction> {
  _AddMenuItem({
    required super.value,
    required this.icon,
    required this.label,
    required this.selected,
    this.description,
    super.enabled = true,
    super.key,
  }) : super(
         height: 50,
         padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
         child: _AddMenuRow(
           icon: icon,
           label: label,
           description: description,
           selected: selected,
           enabled: enabled,
         ),
       );

  final IconData icon;
  final String label;
  final String? description;
  final bool selected;
}

class _AddMenuMessage extends PopupMenuItem<_AddMenuAction> {
  _AddMenuMessage({required String label, super.key})
    : super(
        enabled: false,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label),
      );
}

class _AddMenuRow extends StatelessWidget {
  const _AddMenuRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    this.description,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final titleColor = enabled ? palette.trace : palette.muted;
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.raised : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Icon(icon, size: 21, color: titleColor),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (description?.trim().isNotEmpty == true) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: palette.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, size: 17, color: palette.active),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerContextChip extends StatelessWidget {
  const _ComposerContextChip({
    required this.icon,
    required this.label,
    required this.onRemove,
    this.thumbnailPath,
    this.onPreview,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onRemove;
  final String? thumbnailPath;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thumbnailPath case final thumbnail?)
            InkWell(
              key: const Key('composer-image-thumbnail'),
              onTap: onPreview,
              borderRadius: BorderRadius.circular(7),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Image.file(
                    File(thumbnail),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: palette.field,
                      child: Icon(icon, size: 18, color: palette.muted),
                    ),
                  ),
                ),
              ),
            )
          else
            Icon(icon, size: 15, color: palette.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 3),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel({
    required this.approval,
    required this.enabled,
    required this.onAccept,
    required this.onDecline,
  });

  final PendingApproval approval;
  final bool enabled;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  /// 构建当前服务器审批请求及其允许、拒绝操作。
  /// Builds the current server approval request with allow and decline actions.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.signalSelected,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            approval.title,
            style: TextStyle(
              color: palette.signal,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (approval.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(approval.detail),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                onPressed: enabled ? onDecline : null,
                child: const Text('拒绝'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: enabled ? onAccept : null,
                child: const Text('仅本次允许'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.width,
    required this.controller,
    required this.onShowGitProject,
  });

  final double width;
  final CodexController controller;
  final Future<void> Function() onShowGitProject;

  /// 构建采用 Codex 信息卡层级的审批与文件变更检查器。
  /// Builds the approval and file-change inspector with Codex information-card hierarchy.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Container(
          key: const Key('codex-environment-card'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.module,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.border),
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '环境信息',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: palette.muted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.35,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _InspectorActionRow(
                    icon: Icons.add_box_outlined,
                    label: '变更',
                    trailing: Text(
                      _fileChangeCountLabel(controller.fileChanges.length),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.active,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: onShowGitProject,
                  ),
                  _InspectorActionRow(
                    icon: Icons.laptop_mac_outlined,
                    label: '本地',
                    trailing: Icon(Icons.expand_more, color: palette.muted),
                    onTap: onShowGitProject,
                  ),
                  _InspectorActionRow(
                    icon: Icons.account_tree_outlined,
                    label: controller.gitProjectStatus?.branch ?? '未检测到分支',
                    trailing: Icon(Icons.expand_more, color: palette.muted),
                    onTap: onShowGitProject,
                  ),
                  _InspectorActionRow(
                    icon: Icons.tune_outlined,
                    label: '提交或推送',
                    onTap: onShowGitProject,
                  ),
                  _InspectorActionRow(
                    icon: Icons.call_merge_outlined,
                    label: '创建拉取请求',
                    onTap: onShowGitProject,
                  ),
                  _InspectorActionRow(
                    icon: Icons.compare_arrows_outlined,
                    label: '比较分支',
                    trailing: Icon(
                      Icons.north_east,
                      size: 20,
                      color: palette.muted,
                    ),
                    onTap: onShowGitProject,
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: palette.border),
                  const SizedBox(height: 16),
                  _InspectorSectionHeader(
                    icon: Icons.description_outlined,
                    label: '任务文件',
                    trailing: Text(
                      _fileChangeCountLabel(controller.fileChanges.length),
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: palette.muted),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _InspectorFileChangesList(
                      changes: controller.fileChanges,
                      turnDiff: controller.turnDiff,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: palette.border),
                  const SizedBox(height: 12),
                  _InspectorThreadRow(threadId: controller.activeThreadId),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _fileChangeCountLabel(int count) => count == 0 ? '暂无' : '$count 个';

class _InspectorSectionHeader extends StatelessWidget {
  const _InspectorSectionHeader({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget trailing;

  /// 构建信息卡内带图标、操作和清晰层级的分组标题。
  /// Builds an information-card section heading with an icon and action.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: palette.trace),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        trailing,
      ],
    );
  }
}

class _InspectorActionRow extends StatelessWidget {
  const _InspectorActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final Widget? trailing;

  /// 构建可打开相应 Git 工作流的 Codex 环境信息行。
  /// Builds a Codex environment row that opens its corresponding Git workflow.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return InkWell(
      onTap: () => unawaited(onTap()),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
        child: Row(
          children: [
            Icon(icon, size: 22, color: palette.trace),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _InspectorThreadRow extends StatelessWidget {
  const _InspectorThreadRow({required this.threadId});

  final String? threadId;

  /// 显示当前任务标识，并在空间受限时截断而不撑破信息卡。
  /// Shows the active task identifier without allowing it to overflow the card.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Row(
      children: [
        Icon(Icons.forum_outlined, size: 18, color: palette.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            threadId ?? '尚未创建任务',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ),
      ],
    );
  }
}

class _InspectorFileChangesList extends StatelessWidget {
  const _InspectorFileChangesList({
    required this.changes,
    required this.turnDiff,
  });

  final List<CodexFileChange> changes;
  final String? turnDiff;

  /// 以信息卡中的紧凑行展示完整任务和单文件 Diff。
  /// Shows task and file diffs as compact rows inside the information card.
  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty && (turnDiff == null || turnDiff!.isEmpty)) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(left: 38, top: 4),
          child: _MutedText('任务执行后，AI 修改的文件会显示在这里。'),
        ),
      );
    }
    return Scrollbar(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (turnDiff case final diff?)
            _InspectorDiffExpansionTile(
              title: '本次任务完整 Diff',
              subtitle: '来自 Codex App Server',
              diff: diff,
            ),
          ...changes.map(
            (change) => _InspectorDiffExpansionTile(
              title: change.path,
              subtitle: change.kind,
              diff: change.diff,
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorDiffExpansionTile extends StatelessWidget {
  const _InspectorDiffExpansionTile({
    required this.title,
    required this.subtitle,
    required this.diff,
  });

  final String title;
  final String subtitle;
  final String diff;

  /// 构建与 Codex 环境信息列表一致的紧凑可展开 Diff 项。
  /// Builds a compact expandable Diff row consistent with Codex environment lists.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        expansionTileTheme: ExpansionTileThemeData(
          iconColor: palette.trace,
          collapsedIconColor: palette.trace,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 10),
        ),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        leading: Icon(
          Icons.description_outlined,
          size: 19,
          color: palette.trace,
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.muted),
        ),
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 33),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
            ),
            child: diff.isEmpty
                ? const _MutedText('App Server 未提供可显示的 Diff。')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText.rich(
                      TextSpan(children: _diffSpans(palette, diff)),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 按 unified Diff 行类型与当前主题语义色为文本片段分配颜色。
  /// Assigns colors to text spans using unified-diff line types and theme semantics.
  List<TextSpan> _diffSpans(YeknomPalette palette, String value) {
    return value
        .split('\n')
        .map((line) {
          final color = switch (line) {
            _ when line.startsWith('+++') || line.startsWith('---') =>
              palette.muted,
            _ when line.startsWith('+') => palette.ack,
            _ when line.startsWith('-') => palette.fault,
            _ when line.startsWith('@@') => palette.active,
            _ => palette.trace,
          };
          return TextSpan(
            text: '$line\n',
            style: TextStyle(color: color),
          );
        })
        .toList(growable: false);
  }
}

class _FileChangesList extends StatelessWidget {
  const _FileChangesList({required this.changes, required this.turnDiff});

  final List<CodexFileChange> changes;
  final String? turnDiff;

  /// 构建任务统一 Diff 与单文件变更的可展开列表。
  /// Builds an expandable list for the task's unified diff and individual file changes.
  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty && (turnDiff == null || turnDiff!.isEmpty)) {
      return const _MutedText('任务执行后，AI 修改的文件和逐行 Diff 会显示在这里。');
    }
    return ListView(
      children: [
        if (turnDiff case final diff?)
          _DiffExpansionTile(
            title: '本次任务完整 Diff',
            subtitle: '来自 Codex App Server',
            diff: diff,
          ),
        ...changes.map(
          (change) => _DiffExpansionTile(
            title: change.path,
            subtitle: change.kind,
            diff: change.diff,
          ),
        ),
      ],
    );
  }
}

class _DiffExpansionTile extends StatelessWidget {
  const _DiffExpansionTile({
    required this.title,
    required this.subtitle,
    required this.diff,
  });

  final String title;
  final String subtitle;
  final String diff;

  /// 构建可展开的单个 Diff 展示项。
  /// Builds one expandable diff presentation item.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(bottom: 10),
      leading: const Icon(Icons.description_outlined, size: 18),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: diff.isEmpty
              ? const _MutedText('App Server 未提供可显示的 Diff。')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText.rich(
                    TextSpan(children: _diffSpans(palette, diff)),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// 按 unified Diff 行类型与当前主题语义色为文本片段分配颜色。
  /// Assigns colors to text spans using unified-diff line types and theme semantics.
  List<TextSpan> _diffSpans(YeknomPalette palette, String value) {
    return value
        .split('\n')
        .map((line) {
          final color = switch (line) {
            _ when line.startsWith('+++') || line.startsWith('---') =>
              palette.muted,
            _ when line.startsWith('+') => palette.ack,
            _ when line.startsWith('-') => palette.fault,
            _ when line.startsWith('@@') => palette.active,
            _ => palette.trace,
          };
          return TextSpan(
            text: '$line\n',
            style: TextStyle(color: color),
          );
        })
        .toList(growable: false);
  }
}

/// 展示可搜索、可按状态筛选并支持显式 Git 操作的项目对话框。
/// Displays a searchable, status-filterable project dialog with explicit Git actions.
class _GitProjectDialog extends StatefulWidget {
  const _GitProjectDialog({required this.controller});

  final CodexController controller;

  @override
  State<_GitProjectDialog> createState() => _GitProjectDialogState();
}

class _GitProjectDialogState extends State<_GitProjectDialog> {
  final TextEditingController _search = TextEditingController();
  GitChangeFilter _filter = GitChangeFilter.all;

  /// 收集提交消息并由用户显式选择仅提交或提交后推送。
  /// Collects a commit message and lets the user explicitly choose commit or commit-and-push.
  Future<void> _commitOrPush() async {
    final message = TextEditingController();
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提交或推送'),
        content: TextField(
          controller: message,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(labelText: '提交消息'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('仅提交'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('提交并推送'),
          ),
        ],
      ),
    );
    final text = message.text.trim();
    message.dispose();
    if (action == null || text.isEmpty) return;
    final committed = await widget.controller.commitGitChanges(text);
    if (committed && action) await widget.controller.pushGitBranch();
  }

  /// 收集 PR 标题并通过本机已认证的 GitHub CLI 创建拉取请求。
  /// Collects a PR title and creates it through the locally authenticated GitHub CLI.
  Future<void> _createPullRequest() async {
    final title = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建拉取请求'),
        content: TextField(
          controller: title,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(labelText: '拉取请求标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final text = title.text.trim();
    title.dispose();
    if (confirmed == true && text.isNotEmpty) {
      await widget.controller.createGitPullRequest(text);
    }
  }

  /// 二次确认后丢弃指定文件的 Git 改动，避免点击行尾按钮即丢失内容。
  /// Discards a file's Git changes only after a second confirmation.
  Future<void> _revertChange(GitProjectChange change) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('还原文件改动？'),
        content: Text('“${change.path}”的暂存区和工作区改动将被丢弃，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('还原'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.revertGitChange(change);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 构建筛选控件、文件级 Git 操作和当前 Diff 预览。
  /// Builds filters, file-level Git actions, and the current Diff preview.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final status = controller.gitProjectStatus;
    final palette = YeknomPalette.of(context);
    final counts = status?.changeCounts;
    final changes =
        status?.filteredChanges(filter: _filter, query: _search.text) ??
        const <GitProjectChange>[];
    return AlertDialog(
      key: const Key('git-project-dialog'),
      title: const Text('Git 项目'),
      content: SizedBox(
        width: 920,
        height: 590,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择文件可查看 Diff、暂存或还原；提交、推送和创建 PR 均需显式确认。'),
            const SizedBox(height: 12),
            if (controller.gitOperationError case final error?) ...[
              Text(error, style: TextStyle(color: palette.fault)),
              const SizedBox(height: 8),
            ],
            if (controller.gitProjectLoading)
              const LinearProgressIndicator()
            else if (controller.gitProjectError case final error?)
              Text(error, style: TextStyle(color: palette.fault))
            else if (status == null || !status.isRepository)
              const Expanded(child: Center(child: Text('当前项目不是 Git 仓库。')))
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('分支：${status.branch ?? 'DETACHED'}')),
                  Chip(label: Text('暂存：${counts!.staged}')),
                  Chip(label: Text('未暂存：${counts.unstaged}')),
                  Chip(label: Text('未跟踪：${counts.untracked}')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('git-change-search'),
                      controller: _search,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 19),
                        hintText: '搜索文件路径',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<GitChangeFilter>(
                    key: const Key('git-change-filter'),
                    value: _filter,
                    onChanged: (value) {
                      if (value != null) setState(() => _filter = value);
                    },
                    items: GitChangeFilter.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 320,
                      child: status.changes.isEmpty
                          ? const Center(child: Text('工作区没有未提交改动。'))
                          : changes.isEmpty
                          ? const Center(child: Text('没有符合筛选条件的文件。'))
                          : ListView.separated(
                              key: const Key('git-change-list'),
                              itemCount: changes.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final change = changes[index];
                                final selected =
                                    controller.gitDiffChange == change;
                                return ListTile(
                                  selected: selected,
                                  selectedTileColor: palette.selected,
                                  dense: true,
                                  leading: Icon(
                                    change.isUntracked
                                        ? Icons.note_add_outlined
                                        : Icons.description_outlined,
                                    size: 18,
                                  ),
                                  title: Text(
                                    change.path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    change.previousPath == null
                                        ? '${change.label} · ${change.code}'
                                        : '${change.label}：${change.previousPath} → ${change.path}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!change.isStaged)
                                        IconButton(
                                          tooltip: '暂存文件',
                                          onPressed:
                                              controller.gitOperationRunning
                                              ? null
                                              : () => controller.stageGitChange(
                                                  change,
                                                ),
                                          icon: const Icon(
                                            Icons.add_box_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: '还原文件改动',
                                        onPressed:
                                            controller.gitOperationRunning
                                            ? null
                                            : () => _revertChange(change),
                                        icon: const Icon(
                                          Icons.restore_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => controller.showGitDiff(change),
                                );
                              },
                            ),
                    ),
                    const VerticalDivider(width: 24),
                    Expanded(
                      child: _GitDiffViewer(
                        change: controller.gitDiffChange,
                        diff: controller.gitDiff,
                        loading: controller.gitDiffLoading,
                        truncated: controller.gitDiffTruncated,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: controller.gitOperationRunning ? null : _commitOrPush,
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: const Text('提交或推送'),
        ),
        TextButton.icon(
          onPressed: controller.gitOperationRunning ? null : _createPullRequest,
          icon: const Icon(Icons.call_merge_outlined, size: 18),
          label: const Text('创建拉取请求'),
        ),
        TextButton.icon(
          onPressed: controller.gitProjectLoading
              ? null
              : controller.refreshGitProject,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('刷新'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 展示只读 Git Diff 的详情面板，不包含暂存、恢复或写入仓库的操作。
/// Displays a read-only Git diff detail panel without staging, restoring, or repository write actions.
class _GitDiffViewer extends StatelessWidget {
  const _GitDiffViewer({
    required this.change,
    required this.diff,
    required this.loading,
    required this.truncated,
  });

  final GitProjectChange? change;
  final String? diff;
  final bool loading;
  final bool truncated;

  /// 构建所选 Git 文件的加载、空状态或可复制 Diff 内容。
  /// Builds loading, empty, or copyable diff content for the selected Git file.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (change == null) return const Center(child: Text('从左侧选择一个文件查看 Diff。'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          change!.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (truncated) ...[
          Container(
            key: const Key('git-diff-truncated-warning'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.warning),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Diff 过大，当前仅显示前 120,000 个字符。')),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: diff == null
                ? const Center(child: Text('正在准备 Diff。'))
                : diff!.isEmpty
                ? const Center(child: Text('Git 未返回可显示的 Diff。'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        diff!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Collapses consecutive low-level tool records into one Codex-style activity
/// disclosure while retaining their order in the conversation timeline.
List<_ConversationTimelineItem> _conversationTimelineItems(
  List<TimelineEntry> entries,
) {
  final items = <_ConversationTimelineItem>[];
  var index = 0;
  while (index < entries.length) {
    final entry = entries[index];
    if (!_isActivityEntry(entry)) {
      items.add(_ConversationTimelineItem.entry(entry, index));
      index++;
      continue;
    }
    final activities = <TimelineEntry>[];
    final firstIndex = index;
    while (index < entries.length && _isActivityEntry(entries[index])) {
      activities.add(entries[index]);
      index++;
    }
    items.add(_ConversationTimelineItem.activities(activities, firstIndex));
  }
  return items;
}

bool _isActivityEntry(TimelineEntry entry) =>
    entry.kind == TimelineKind.tool ||
    (entry.kind == TimelineKind.command && entry.title != '文件变更');

class _ConversationTimelineItem {
  const _ConversationTimelineItem.entry(this.entry, this.entryIndex)
    : activities = null;

  const _ConversationTimelineItem.activities(this.activities, this.entryIndex)
    : entry = null;

  final TimelineEntry? entry;
  final List<TimelineEntry>? activities;
  final int entryIndex;
}

class _TimelineActivityList extends StatelessWidget {
  const _TimelineActivityList({
    required this.entries,
    required this.expanded,
    required this.onExpandedChanged,
    super.key,
  });

  final List<TimelineEntry> entries;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final summary = _activitySummary(entries);
    return Semantics(
      container: true,
      label: summary,
      expanded: expanded,
      button: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onExpandedChanged(!expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 6, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.manage_search_outlined,
                    size: 20,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: palette.trace,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 19,
                    color: palette.muted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 5),
            for (final entry in entries) _TimelineActivityRow(entry: entry),
          ],
        ],
      ),
    );
  }
}

String _activitySummary(List<TimelineEntry> entries) {
  final actions = <String>{};
  for (final entry in entries) {
    final label = '${entry.title}\n${entry.detail}'.toLowerCase();
    if (entry.kind == TimelineKind.command) {
      actions.add('运行了命令');
    } else if (label.contains('read') || label.contains('读取')) {
      actions.add('读取了文件');
    } else if (label.contains('search') || label.contains('搜索')) {
      actions.add('进行了搜索');
    } else {
      actions.add('使用了工具');
    }
  }
  return '已${actions.join('并')}';
}

class _TimelineActivityRow extends StatelessWidget {
  const _TimelineActivityRow({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final label = _activityLabel(entry);
    return Tooltip(
      message: entry.detail,
      waitDuration: const Duration(milliseconds: 450),
      child: Semantics(
        label: '$label。${entry.detail}',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
          child: Row(
            children: [
              Icon(_activityIcon(entry), size: 19, color: palette.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.trace),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _activityLabel(TimelineEntry entry) {
  if (entry.kind == TimelineKind.command) {
    final command = entry.detail.split('\n').first.trim();
    return command.isEmpty ? '已运行命令' : '已运行 $command';
  }
  return entry.title.isEmpty ? '已使用工具' : entry.title;
}

IconData _activityIcon(TimelineEntry entry) {
  if (entry.kind == TimelineKind.command) return Icons.terminal_outlined;
  final label = '${entry.title}\n${entry.detail}'.toLowerCase();
  if (label.contains('read') || label.contains('读取')) {
    return Icons.menu_book_outlined;
  }
  if (label.contains('search') || label.contains('搜索')) {
    return Icons.search;
  }
  if (label.contains('image') || label.contains('图片')) {
    return Icons.image_outlined;
  }
  return Icons.build_outlined;
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry(this.entry, {this.onAdjustDirection});

  final TimelineEntry entry;
  final VoidCallback? onAdjustDirection;

  /// 按时间线条目类型构建消息或系统事件视图。
  /// Builds a message or system-event view based on the timeline entry kind.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (entry.kind == TimelineKind.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectionArea(child: Text(entry.detail)),
              ),
              if (entry.imagePaths.isNotEmpty) ...[
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final path in entry.imagePaths)
                        _TimelineImage(path: path),
                    ],
                  ),
                ),
              ],
              if (onAdjustDirection != null) ...[
                const SizedBox(height: 5),
                TextButton.icon(
                  key: const Key('adjust-direction-button'),
                  onPressed: onAdjustDirection,
                  icon: const Icon(Icons.reply_outlined, size: 17),
                  label: const Text('调整方向'),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.muted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final color = switch (entry.kind) {
      TimelineKind.agent => palette.ack,
      TimelineKind.command => palette.warning,
      TimelineKind.tool => palette.active,
      TimelineKind.approval => palette.signal,
      TimelineKind.error => palette.fault,
      TimelineKind.system => palette.muted,
      TimelineKind.user => throw StateError('Handled above.'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.title,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        if (entry.detail.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (entry.kind == TimelineKind.agent)
            _AgentMarkdown(entry.detail)
          else
            SelectionArea(child: Text(entry.detail)),
        ],
      ],
    );
  }
}

/// 在用户消息中展示随消息发送的本地图片缩略图。
/// Renders thumbnails for local images sent alongside a user message.
class _TimelineImage extends StatelessWidget {
  const _TimelineImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(path),
        key: ValueKey('timeline-image-$path'),
        width: 180,
        height: 130,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// 将 Codex 回复按 GitHub Flavored Markdown 渲染，并保持与工作台主题一致。
/// Renders Codex replies as GitHub Flavored Markdown while matching the workbench theme.
class _AgentMarkdown extends StatelessWidget {
  const _AgentMarkdown(this.data);

  final String data;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.5);
    return SelectionArea(
      key: const Key('agent-markdown-selection'),
      child: MarkdownBody(
        data: data,
        selectable: false,
        onTapLink: (_, href, _) async {
          final uri = href == null ? null : Uri.tryParse(href);
          if (uri == null ||
              !const {
                'http',
                'https',
                'mailto',
              }.contains(uri.scheme.toLowerCase())) {
            return;
          }
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: body,
          pPadding: EdgeInsets.zero,
          blockSpacing: 8,
          listIndent: 22,
          listBullet: body,
          a: body?.copyWith(
            color: palette.active,
            decoration: TextDecoration.underline,
            decorationColor: palette.active.withValues(alpha: 0.65),
          ),
          code: body?.copyWith(
            color: palette.trace,
            fontFamily: 'monospace',
            fontSize: 12,
            backgroundColor: palette.field,
          ),
          codeblockPadding: const EdgeInsets.all(12),
          codeblockDecoration: BoxDecoration(
            color: palette.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          blockquotePadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          blockquoteDecoration: BoxDecoration(
            color: palette.raised,
            border: Border(left: BorderSide(color: palette.active, width: 3)),
          ),
          tableBorder: TableBorder.all(color: palette.border),
          tableHead: body?.copyWith(fontWeight: FontWeight.w700),
          tableBody: body,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  /// 构建表示运行时状态的紧凑彩色标签。
  /// Builds a compact colored pill representing runtime status.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({this.label = 'OpenAI / App Server'});

  final String label;

  /// 构建 Provider 或运行时边界的紧凑说明标签。
  /// Builds a compact label for a provider or runtime boundary.
  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// 在保留测试控制器注入能力的同时，从 Riverpod 读取应用级控制器。
/// Reads the app controller from Riverpod while preserving explicit test injection.
class _ControllerBuilder extends ConsumerWidget {
  const _ControllerBuilder({required this.builder, this.overrideController});

  final CodexController? overrideController;
  final Widget Function(BuildContext context, CodexController controller)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = overrideController;
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => builder(context, controller),
      );
    }
    return builder(context, ref.watch(codexControllerProvider)!);
  }
}

class _HistoryThreadTile extends StatelessWidget {
  const _HistoryThreadTile({
    required this.thread,
    required this.selected,
    required this.pinned,
    required this.statusIndicator,
    required this.running,
    required this.enabled,
    required this.selectionMode,
    required this.batchSelected,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
    required this.onDelete,
    required this.onTogglePin,
  });

  final CodexThread thread;
  final bool selected;
  final bool pinned;
  final _ThreadStatusIndicator? statusIndicator;
  final bool running;
  final bool enabled;
  final bool selectionMode;
  final bool batchSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  /// 构建带有恢复、重命名和归档操作的历史线程项。
  /// Builds a history-thread item with resume, rename, and archive actions.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Material(
      color: selected ? palette.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 6, 1, 6),
          child: Row(
            children: [
              if (selectionMode)
                Checkbox(
                  value: batchSelected,
                  onChanged: enabled ? (_) => onTap() : null,
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? palette.trace : palette.muted,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (running)
                Tooltip(
                  message: '任务进行中',
                  child: SizedBox(
                    key: const Key('sidebar-running-task-indicator'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: palette.active,
                    ),
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (statusIndicator case final indicator?)
                      _ThreadStatusMark(indicator: indicator),
                    PopupMenuButton<_ThreadAction>(
                      tooltip: '任务选项',
                      enabled: enabled && !selectionMode,
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      onSelected: (action) {
                        switch (action) {
                          case _ThreadAction.rename:
                            onRename();
                          case _ThreadAction.archive:
                            onArchive();
                          case _ThreadAction.delete:
                            onDelete();
                          case _ThreadAction.pin:
                            onTogglePin();
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _ThreadAction.pin,
                          child: Text(pinned ? '取消置顶' : '置顶'),
                        ),
                        const PopupMenuItem(
                          value: _ThreadAction.rename,
                          child: Text('重命名'),
                        ),
                        const PopupMenuItem(
                          value: _ThreadAction.archive,
                          child: Text('归档'),
                        ),
                        const PopupMenuItem(
                          value: _ThreadAction.delete,
                          child: Text('永久删除'),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isRunningThreadStatus(String? status) {
  final normalized = status?.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z]'),
    '',
  );
  return normalized == 'active' ||
      normalized == 'inprogress' ||
      normalized == 'running';
}

enum _ThreadStatusIndicator { completed, error }

/// Maps App Server thread status values to the compact sidebar outcome marks.
/// 将 App Server 线程状态映射为侧栏紧凑的结果提示图标。
_ThreadStatusIndicator? _threadStatusIndicator(String? status) {
  final normalized = status?.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z]'),
    '',
  );
  return switch (normalized) {
    'idle' ||
    'completed' ||
    'complete' ||
    'done' ||
    'success' ||
    'succeeded' => _ThreadStatusIndicator.completed,
    'systemerror' ||
    'error' ||
    'failed' ||
    'failure' ||
    'errored' => _ThreadStatusIndicator.error,
    _ => null,
  };
}

class _ThreadStatusMark extends StatelessWidget {
  const _ThreadStatusMark({required this.indicator});

  final _ThreadStatusIndicator indicator;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final completed = indicator == _ThreadStatusIndicator.completed;
    return Tooltip(
      message: completed ? '任务已完成' : '任务执行出错',
      child: Icon(
        completed ? Icons.info : Icons.error,
        key: Key(
          completed
              ? 'sidebar-completed-task-indicator'
              : 'sidebar-error-task-indicator',
        ),
        size: 16,
        color: completed ? palette.active : palette.fault,
      ),
    );
  }
}

enum _ThreadAction { pin, rename, archive, delete }

enum _HistoryAction { archived, batchArchive, export, import }

enum _ThemeAction {
  system,
  light,
  dark,
  workbench,
  cobalt,
  orchid,
  graphite,
  obsidian,
  midnight,
  blackberry,
  sage;

  /// 返回对应配色预设；显示模式操作没有预设。
  /// Returns the corresponding color preset; display-mode actions have none.
  YeknomColorPreset? get preset => switch (this) {
    _ThemeAction.workbench => YeknomColorPreset.workbench,
    _ThemeAction.cobalt => YeknomColorPreset.cobalt,
    _ThemeAction.orchid => YeknomColorPreset.orchid,
    _ThemeAction.graphite => YeknomColorPreset.graphite,
    _ThemeAction.obsidian => YeknomColorPreset.obsidian,
    _ThemeAction.midnight => YeknomColorPreset.midnight,
    _ThemeAction.blackberry => YeknomColorPreset.blackberry,
    _ThemeAction.sage => YeknomColorPreset.sage,
    _ => null,
  };
}

/// 返回显示模式的本地化名称。
/// Returns the localized name for a display mode.
String _themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

/// 返回显示模式在顶部栏中使用的图标。
/// Returns the icon used for a display mode in the top bar.
IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

/// 返回 UI Kit 配色预设的本地化名称。
/// Returns the localized name for a UI Kit color preset.
String _themePresetLabel(YeknomColorPreset preset) => switch (preset) {
  YeknomColorPreset.workbench => '工作台',
  YeknomColorPreset.cobalt => '钴蓝',
  YeknomColorPreset.orchid => '兰紫',
  YeknomColorPreset.graphite => '石墨',
  YeknomColorPreset.obsidian => '黑曜',
  YeknomColorPreset.midnight => '午夜',
  YeknomColorPreset.blackberry => '黑莓',
  YeknomColorPreset.sage => '鼠尾草',
};

class _ArchivedThreadTile extends StatelessWidget {
  const _ArchivedThreadTile({
    required this.thread,
    required this.enabled,
    required this.restoring,
    required this.onRestore,
    required this.onDelete,
  });

  final CodexThread thread;
  final bool enabled;
  final bool restoring;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  /// 构建带恢复操作与进行状态的归档线程项。
  /// Builds an archived-thread item with restore action and progress state.
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: thread.status == null ? null : Text(thread.status!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: enabled ? onRestore : null,
            icon: restoring
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.unarchive_outlined, size: 18),
            label: Text(restoring ? '恢复中' : '恢复'),
          ),
          IconButton(
            tooltip: '永久删除任务',
            onPressed: enabled && !restoring ? onDelete : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.data);

  final String data;

  /// 构建使用低强调颜色的辅助说明文本。
  /// Builds helper text using a low-emphasis color.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Text(data, style: TextStyle(color: palette.muted, fontSize: 12));
  }
}
