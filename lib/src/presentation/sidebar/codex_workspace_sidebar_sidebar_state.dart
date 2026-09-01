// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_plugin_mark.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_task_count_request.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_workspace_tile.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_section_label.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_details_card.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_result.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_dialog.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_menu_action.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_task_list_item.dart';

class SidebarState extends State<Sidebar> with TickerProviderStateMixin {
  bool _batchMode = false;
  String? _batchWorkspacePath;
  final Set<String> _selectedThreadIds = {};

  final Map<String, bool> _workspaceExpanded = {};
  final Map<String, AnimationController> _workspaceExpansionControllers = {};
  final ScrollController _taskListScrollController = ScrollController();
  OverlayEntry? _workspaceDetailsEntry;
  Timer? _workspaceDetailsShowTimer;
  Timer? _workspaceDetailsHideTimer;

  bool _isWorkspaceExpanded(String path) => _workspaceExpanded[path] ?? true;

  bool _shouldBuildWorkspaceContents(String path) =>
      _isWorkspaceExpanded(path) ||
      (_workspaceExpansionControllers[path]?.isAnimating ?? false);

  double _workspaceExpansionProgress(String path) {
    final controller = _workspaceExpansionControllers[path];
    if (controller == null) return _isWorkspaceExpanded(path) ? 1 : 0;
    return Curves.easeOutCubic.transform(controller.value).clamp(0.001, 1.0);
  }

  void _pruneWorkspaceExpansionControllers(Set<String> workspacePaths) {
    final stalePaths = _workspaceExpansionControllers.keys
        .where((path) => !workspacePaths.contains(path))
        .toList(growable: false);
    for (final path in stalePaths) {
      final controller = _workspaceExpansionControllers.remove(path);
      controller
        ?..removeListener(_onWorkspaceExpansionTick)
        ..dispose();
      _workspaceExpanded.remove(path);
    }
  }

  void _setBatchMode(bool enabled) {
    setState(() {
      _batchMode = enabled;
      _batchWorkspacePath = enabled ? widget.controller.workspacePath : null;
      _selectedThreadIds.clear();
    });
  }

  void _toggleWorkspaceExpanded(String path) {
    final controller = _workspaceExpansionControllers.putIfAbsent(path, () {
      final animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 180),
        value: _isWorkspaceExpanded(path) ? 1 : 0,
      );
      animationController.addStatusListener((status) {
        if (!mounted || status != AnimationStatus.dismissed) return;
        setState(() {});
      });
      animationController.addListener(_onWorkspaceExpansionTick);
      return animationController;
    });
    setState(() {
      final expand = switch (controller.status) {
        AnimationStatus.reverse => true,
        AnimationStatus.forward => false,
        _ => !_isWorkspaceExpanded(path),
      };
      if (expand) {
        _workspaceExpanded[path] = true;
        controller.forward();
      } else {
        _workspaceExpanded[path] = false;
        controller.reverse();
      }
    });
  }

  void _onWorkspaceExpansionTick() {
    if (mounted) setState(() {});
  }

  /// Opens a new task in the project whose row owns the action. A project's
  /// hover action may be invoked while another project is active, so switch
  /// and reconnect before clearing the conversation state.
  /// 在项目行悬停菜单中创建任务时，先切换到该行所属项目，避免新任务仍落在
  /// 当前前台项目下。
  void _startNewConversationForWorkspace(String path) {
    final controller = widget.controller;
    if (path != controller.workspacePath) {
      unawaited(_switchWorkspaceThenStartNewConversation(path));
      return;
    }
    widget.onNewConversation();
  }

  Future<void> _switchWorkspaceThenStartNewConversation(String path) async {
    final switched = await widget.controller.selectWorkspaceAndReconnect(path);
    if (!mounted || !switched || widget.controller.workspacePath != path) {
      return;
    }
    widget.onNewConversation();
  }

  @override
  void dispose() {
    _workspaceDetailsShowTimer?.cancel();
    _workspaceDetailsHideTimer?.cancel();
    _workspaceDetailsEntry?.remove();
    _taskListScrollController.dispose();
    for (final controller in _workspaceExpansionControllers.values) {
      controller
        ..removeListener(_onWorkspaceExpansionTick)
        ..dispose();
    }
    super.dispose();
  }

  /// Opens the global task search surface from the project-column toolbar.
  /// 搜索面板集中展示已加载项目中的任务，并保留常用的工作区操作。
  void _showTaskSearch() {
    final controller = widget.controller;
    final configuredWorkspaces = controller.workspaceConfigurations;
    final workspaces = configuredWorkspaces.isNotEmpty
        ? configuredWorkspaces
        : controller.workspacePath == null
        ? const <WorkspaceConfiguration>[]
        : [WorkspaceConfiguration(primaryPath: controller.workspacePath!)];
    final results = <TaskSearchResult>[];
    for (final workspace in workspaces) {
      final threads = workspace.primaryPath == controller.workspacePath
          ? controller.threads
          : (controller.workspaceTaskListFor(workspace.primaryPath)?.threads ??
                const <CodexThread>[]);
      for (final thread in threads) {
        results.add(
          TaskSearchResult(
            thread: thread,
            workspacePath: workspace.primaryPath,
            workspaceName:
                workspace.name ?? workspaceDirectoryName(workspace.primaryPath),
          ),
        );
      }
    }
    showDialog<void>(
      context: context,
      builder: (context) => TaskSearchDialog(
        results: results,
        canCreateTask: controller.canCreateThread,
        canOpenTask: (result) =>
            result.workspacePath == controller.workspacePath
            ? controller.canSwitchThreads
            : controller.canChangePrimaryWorkspace,
        canSearchFiles: controller.workspacePath != null,
        onOpenTask: (result) {
          widget.onOpenConversation();
          return controller.openWorkspaceThread(
            workspace: result.workspacePath,
            thread: result.thread,
          );
        },
        onNewTask: widget.onNewConversation,
        onOpenWorkspace: widget.onChooseWorkspace,
        onSearchFiles: widget.onShowGitProject,
      ),
    );
  }

  Future<void> _showHelpMenu(BuildContext anchorContext) async {
    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox) return;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final viewport = MediaQuery.sizeOf(context);
    const menuWidth = 280.0;
    const menuHeight = 168.0;
    final left = (topLeft.dx - menuWidth + renderObject.size.width).clamp(
      8.0,
      viewport.width - menuWidth - 8.0,
    );
    final top = (topLeft.dy - menuHeight - 8.0).clamp(
      8.0,
      viewport.height - menuHeight - 8.0,
    );
    final action = await showMenu<SidebarHelpAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        viewport.width - left - menuWidth,
        viewport.height - top - menuHeight,
      ),
      items: const [
        PopupMenuItem(
          key: Key('help-chrome-extension'),
          value: SidebarHelpAction.chromeExtension,
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.language, size: 20),
              title: Text('设置 Chrome 扩展程序'),
            ),
          ),
        ),
        PopupMenuItem(
          key: Key('help-keyboard-shortcuts'),
          value: SidebarHelpAction.keyboardShortcuts,
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.keyboard_alt_outlined, size: 20),
              title: Text('键盘快捷键'),
            ),
          ),
        ),
        PopupMenuItem(
          key: Key('help-open-help'),
          value: SidebarHelpAction.help,
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.support_outlined, size: 20),
              title: Text('帮助'),
            ),
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case SidebarHelpAction.chromeExtension:
        try {
          await launchUrl(
            Uri.parse('https://chatgpt.com/codex/chrome-extension'),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {}
      case SidebarHelpAction.keyboardShortcuts:
        _showKeyboardShortcutsDialog();
      case SidebarHelpAction.help:
        try {
          await launchUrl(
            Uri.parse('https://help.openai.com/'),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {}
    }
  }

  Future<void> _showKeyboardShortcutsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('sidebar-keyboard-shortcuts-dialog'),
        title: const Text('键盘快捷键'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('新对话'), trailing: Text('⌘ N')),
            ListTile(title: Text('搜索聊天'), trailing: Text('⌘ K')),
            ListTile(title: Text('关闭弹窗'), trailing: Text('Esc')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  /// 将当前选中的活跃任务提交给带二次确认的批量归档操作。
  /// Sends selected active tasks to the confirmation-backed bulk archive action.
  Future<void> _archiveSelectedThreads(CodexController controller) async {
    final selected = controller.threads
        .where((thread) => _selectedThreadIds.contains(thread.id))
        .toList(growable: false);
    final result = await widget.onArchiveThreads(selected);
    if (!mounted || result == null) return;
    setState(() {
      _selectedThreadIds.removeAll(result.archivedIds);
      if (_selectedThreadIds.isEmpty && result.archivedIds.isNotEmpty) {
        _batchMode = false;
        _batchWorkspacePath = null;
      }
    });
  }

  /// 在项目停留一段时间后显示详情卡片，避免快速掠过侧栏时弹出卡片。
  /// Shows the detail card after a pointer dwell, avoiding popups while scanning the sidebar.
  void _scheduleWorkspaceDetailsShow(
    BuildContext anchorContext,
    WorkspaceConfiguration workspace,
  ) {
    _workspaceDetailsShowTimer?.cancel();
    _workspaceDetailsHideTimer?.cancel();
    _workspaceDetailsShowTimer = Timer(codexHoverPopupDelay, () {
      _workspaceDetailsShowTimer = null;
      if (mounted) _showWorkspaceDetails(anchorContext, workspace);
    });
  }

  /// 显示延迟后的项目详情卡片；卡片本身也是可悬停的，便于把鼠标移入查看。
  /// Shows the delayed detail card; the card keeps itself open while the pointer enters it.
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
        child: ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              final taskCount = isActive
                  ? controller.threads.length
                  : ref
                        .watch(
                          workspaceTaskCountProvider(
                            WorkspaceTaskCountRequest(
                              controller: controller,
                              path: workspace.primaryPath,
                            ),
                          ),
                        )
                        .when(
                          data: (value) => value,
                          loading: () => null,
                          error: (_, _) => -1,
                        );
              return MouseRegion(
                onEnter: (_) => _workspaceDetailsHideTimer?.cancel(),
                onExit: (_) => _scheduleWorkspaceDetailsHide(),
                child: WorkspaceDetailsCard(
                  workspace: workspace,
                  taskCount: taskCount,
                  pinned: controller.isWorkspacePinned(workspace.primaryPath),
                  onTogglePin: () {
                    unawaited(
                      controller
                          .toggleWorkspacePinned(workspace.primaryPath)
                          .then((_) {
                            if (_workspaceDetailsEntry == entry) {
                              entry.markNeedsBuild();
                            }
                          }),
                    );
                  },
                  onEditProject: (_) {
                    _hideWorkspaceDetails();
                    widget.onEditWorkspace(workspace.primaryPath);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    _workspaceDetailsEntry = entry;
    overlay.insert(entry);
  }

  void _scheduleWorkspaceDetailsHide() {
    _workspaceDetailsShowTimer?.cancel();
    _workspaceDetailsShowTimer = null;
    _workspaceDetailsHideTimer?.cancel();
    _workspaceDetailsHideTimer = Timer(
      const Duration(milliseconds: 180),
      _hideWorkspaceDetails,
    );
  }

  void _hideWorkspaceDetails() {
    _workspaceDetailsShowTimer?.cancel();
    _workspaceDetailsShowTimer = null;
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
    final action = await showMenu<WorkspaceAction>(
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
          value: WorkspaceAction.pin,
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.push_pin_outlined),
              title: Text('置顶'),
            ),
          ),
        ),
        PopupMenuItem(
          value: WorkspaceAction.edit,
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined),
              title: Text('编辑'),
            ),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: WorkspaceAction.worktree,
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.call_split_outlined),
              title: Text('创建永久工作树'),
            ),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: WorkspaceAction.archive,
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.archive_outlined),
              title: Text('归档聊天'),
            ),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: WorkspaceAction.remove,
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.close),
              title: Text('移除项目'),
            ),
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case WorkspaceAction.pin:
        await widget.controller.toggleWorkspacePinned(workspace.primaryPath);
      case WorkspaceAction.edit:
        widget.onEditWorkspace(workspace.primaryPath);
      case WorkspaceAction.worktree:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('永久工作树功能暂未接入。')));
      case WorkspaceAction.archive:
        if (workspace.primaryPath != widget.controller.workspacePath) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先切换到该项目再批量归档任务。')));
        } else if (widget.controller.threads.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('当前项目没有可归档的任务。')));
        } else {
          _setBatchMode(true);
        }
      case WorkspaceAction.remove:
        await widget.controller.forgetWorkspace(workspace.primaryPath);
    }
  }

  /// 构建树中的任务文件节点；任务操作仍沿用原有菜单和批量选择行为。
  /// Builds a task-file node in the tree while preserving the existing actions.
  Widget _buildThreadNode(
    CodexController controller,
    CodexThread thread, {
    bool isActiveWorkspace = true,
    required String workspacePath,
    required bool pinned,
    bool acknowledged = false,
  }) {
    final indicator = threadStatusIndicator(thread.status);
    final selected =
        isActiveWorkspace && controller.activeThreadId == thread.id;
    final currentRunningThread = isActiveWorkspace
        ? controller.isThreadExecutionActive(thread)
        : controller.isThreadRunningInWorkspace(thread.id, workspacePath);
    final updatingThread =
        isActiveWorkspace && controller.isUpdatingThread(thread.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: HistoryThreadTile(
        thread: thread,
        selected: selected,
        pinned: pinned,
        statusIndicator:
            indicator == ThreadStatusIndicator.completed &&
                (acknowledged ||
                    controller.isCompletedThreadAcknowledged(thread.id))
            ? null
            : indicator,
        running: currentRunningThread,
        processing: updatingThread,
        enabled: isActiveWorkspace
            ? controller.canSwitchThreads &&
                  !controller.isUpdatingThread(thread.id)
            : controller.canChangePrimaryWorkspace,
        selectionMode: isActiveWorkspace && _batchMode,
        batchSelected: _selectedThreadIds.contains(thread.id),
        onTap: () {
          // Selecting any task is also the explicit way back from a library
          // workspace to the conversation workbench.
          widget.onOpenConversation();
          // The active row remains clickable for focus/feedback while its
          // turn runs, but must not attempt to resume or replace the thread.
          if (currentRunningThread && controller.activeThreadId == thread.id) {
            return;
          }
          if (isActiveWorkspace && _batchMode) {
            setState(() {
              if (!_selectedThreadIds.add(thread.id)) {
                _selectedThreadIds.remove(thread.id);
              }
            });
          } else {
            // A thread refresh can deliver its completed state after this
            // tap.  Record the visit independently of the currently rendered
            // status so an old completion reminder cannot reappear while the
            // user switches between tasks.
            unawaited(
              controller.openWorkspaceThread(
                workspace: workspacePath,
                thread: thread,
              ),
            );
          }
        },
        actionsEnabled: isActiveWorkspace,
        onRename: isActiveWorkspace
            ? () => widget.onRenameThread(thread)
            : null,
        onArchive: isActiveWorkspace
            ? currentRunningThread
                  ? null
                  : () => widget.onArchiveThread(thread)
            : null,
        onDelete: isActiveWorkspace
            ? () => widget.onDeleteThread(thread)
            : null,
        onTogglePin: isActiveWorkspace
            ? () => controller.toggleThreadPinned(thread)
            : null,
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
    if (_batchMode && _batchWorkspacePath != activePath) {
      _batchMode = false;
      _batchWorkspacePath = null;
      _selectedThreadIds.clear();
    }
    final visibleThreads = [
      ...controller.threads.where(
        (thread) => controller.isThreadPinned(thread.id),
      ),
      ...controller.threads.where(
        (thread) => !controller.isThreadPinned(thread.id),
      ),
    ];
    final hasPinnedThreads = controller.threads.any((thread) {
      return controller.isThreadPinned(thread.id);
    });
    final pinnedThreads = visibleThreads
        .where((thread) => controller.isThreadPinned(thread.id))
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
    _pruneWorkspaceExpansionControllers(
      workspaces.map((workspace) => workspace.primaryPath).toSet(),
    );
    final workspaceThreadsByPath = <String, List<CodexThread>>{};
    final workspaceProjectThreadsByPath = <String, List<CodexThread>>{};
    for (final workspace in workspaces) {
      final threads = workspace.primaryPath == activePath
          ? controller.threads
          : (controller.workspaceTaskListFor(workspace.primaryPath)?.threads ??
                const <CodexThread>[]);
      final pinnedIds = workspace.primaryPath == activePath
          ? controller.pinnedThreadIds
          : (controller
                    .workspaceTaskListFor(workspace.primaryPath)
                    ?.pinnedIds ??
                const <String>{});
      workspaceThreadsByPath[workspace.primaryPath] = threads;
      workspaceProjectThreadsByPath[workspace.primaryPath] = threads
          .where(
            (thread) =>
                (workspace.primaryPath != activePath ||
                !pinnedIds.contains(thread.id)),
          )
          .toList(growable: false);
    }
    // Keep the project tree lazy. A Column inside SingleChildScrollView lays
    // out every task in every expanded project on each controller update;
    // live task state and completion indicators can otherwise make a large
    // conversation library feel like its scroll is blocked.
    final taskListItems = <SidebarTaskListItem>[];
    void addTaskListItem(
      double extent,
      Widget Function() builder, {
      String? animatedWorkspacePath,
    }) {
      final progress = animatedWorkspacePath == null
          ? 1.0
          : _workspaceExpansionProgress(animatedWorkspacePath);
      taskListItems.add(
        SidebarTaskListItem(
          extent: extent * progress,
          builder: (_) {
            final child = builder();
            if (animatedWorkspacePath == null) return child;
            if (progress <= 0.001) return const SizedBox.shrink();
            return ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: progress,
                  child: child,
                ),
              ),
            );
          },
        ),
      );
    }

    if (hasPinnedThreads) {
      addTaskListItem(12, () => const SidebarSectionLabel(label: '置顶'));
      addTaskListItem(2, () => const SizedBox(height: 2));
      for (final thread in pinnedThreads) {
        addTaskListItem(
          32,
          () => _buildThreadNode(
            controller,
            thread,
            workspacePath: activePath!,
            pinned: true,
          ),
        );
      }
      addTaskListItem(12, () => const SizedBox(height: 12));
    }
    for (final workspace in workspaces) {
      final workspacePath = workspace.primaryPath;
      final isActiveWorkspace = workspacePath == activePath;
      final projectThreads = workspaceProjectThreadsByPath[workspacePath]!;
      final projectAllThreads = workspaceThreadsByPath[workspacePath]!;
      addTaskListItem(
        32,
        () => SidebarWorkspaceTile(
          key: ValueKey('sidebar-workspace-$workspacePath'),
          workspace: workspace,
          active: workspacePath == controller.workspacePath,
          pinned: controller.isWorkspacePinned(workspacePath),
          onMore: (anchorContext) =>
              _showWorkspaceActions(anchorContext, workspace),
          onEdit: (_) => _startNewConversationForWorkspace(workspacePath),
          canCreateTask:
              !workspace.isUnrooted &&
              controller.canCreateThread &&
              (isActiveWorkspace || controller.canChangePrimaryWorkspace),
          expanded: _isWorkspaceExpanded(workspacePath),
          onToggleExpanded: () => _toggleWorkspaceExpanded(workspacePath),
          onHoverStart: (anchorContext) =>
              _scheduleWorkspaceDetailsShow(anchorContext, workspace),
          onHoverEnd: _scheduleWorkspaceDetailsHide,
        ),
      );
      // Keep the project surface visually distinct from its child task rows.
      if (_shouldBuildWorkspaceContents(workspacePath)) {
        addTaskListItem(
          4,
          () => const SizedBox(height: 4),
          animatedWorkspacePath: workspacePath,
        );
      }
      if (_shouldBuildWorkspaceContents(workspacePath)) {
        if (isActiveWorkspace) {
          if (controller.threadsError case final error?) {
            addTaskListItem(
              28,
              () => Padding(
                padding: const EdgeInsets.only(left: 34, top: 4),
                child: MutedText(error),
              ),
              animatedWorkspacePath: workspacePath,
            );
          } else if (projectThreads.isEmpty && projectAllThreads.isEmpty) {
            addTaskListItem(
              24,
              () => const Padding(
                padding: EdgeInsets.only(left: 34, top: 4),
                child: MutedText('暂无历史任务；发送第一条消息后会创建。'),
              ),
              animatedWorkspacePath: workspacePath,
            );
          } else {
            for (final thread in projectThreads) {
              addTaskListItem(
                // The batch checkbox keeps a 48px tap target inside the
                // task's 4px vertical padding, so the row needs 56px.
                _batchMode ? 56 : 32,
                () => _buildThreadNode(
                  controller,
                  thread,
                  isActiveWorkspace: true,
                  workspacePath: workspacePath,
                  pinned: controller.isThreadPinned(thread.id),
                ),
                animatedWorkspacePath: workspacePath,
              );
            }
          }
        } else if (controller.workspaceTaskListFor(workspacePath) != null) {
          final pinnedIds =
              controller.workspaceTaskListFor(workspacePath)?.pinnedIds ??
              const <String>{};
          final acknowledgedIds =
              controller.workspaceTaskListFor(workspacePath)?.acknowledgedIds ??
              const <String>{};
          for (final thread in projectThreads) {
            addTaskListItem(
              32,
              () => _buildThreadNode(
                controller,
                thread,
                isActiveWorkspace: false,
                workspacePath: workspacePath,
                pinned: pinnedIds.contains(thread.id),
                acknowledged: acknowledgedIds.contains(thread.id),
              ),
              animatedWorkspacePath: workspacePath,
            );
          }
        }
      }
      addTaskListItem(5, () => const SizedBox(height: 5));
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
                  key: const Key('task-search-button'),
                  tooltip: '搜索聊天',
                  onPressed: _showTaskSearch,
                  icon: const Icon(Icons.search, size: 17),
                ),
                IconButton(
                  key: const Key('sidebar-create-workspace-button'),
                  tooltip: controller.canCreateWorkspace
                      ? '新建工作区'
                      : '正在保存项目，请稍候。',
                  visualDensity: VisualDensity.compact,
                  onPressed: controller.canCreateWorkspace
                      ? widget.onCreateWorkspace
                      : null,
                  icon: const Icon(Icons.add, size: 17),
                ),
                IconButton(
                  key: const Key('sidebar-manage-workspaces-button'),
                  tooltip: '管理工作区',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onChooseWorkspace,
                  icon: const Icon(Icons.tune, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SidebarMenuAction(
              key: const Key('sidebar-new-chat-button'),
              icon: Icons.edit_outlined,
              label: '新对话',
              enabled: controller.canCreateThread,
              onTap: widget.onNewConversation,
            ),
            SidebarMenuAction(
              key: const Key('sidebar-pull-requests-button'),
              icon: Icons.call_merge_outlined,
              label: '拉取请求',
              enabled: controller.workspacePath != null,
              selected: widget.destination == WorkspaceDestination.pullRequests,
              onTap: () => unawaited(widget.onShowPullRequests()),
            ),
            SidebarMenuAction(
              key: const Key('sidebar-scheduled-tasks-button'),
              icon: Icons.schedule_outlined,
              label: '已安排',
              enabled: controller.workspacePath != null,
              selected:
                  widget.destination == WorkspaceDestination.scheduledTasks,
              onTap: () => unawaited(widget.onShowScheduledTasks()),
            ),
            SidebarMenuAction(
              key: const Key('sidebar-plugins-button'),
              leading: buildCodexPluginMark(color: palette.trace, size: 16),
              label: '插件',
              selected: widget.destination == WorkspaceDestination.plugins,
              onTap: () => unawaited(widget.onShowPlugins()),
            ),
            const SizedBox(height: 9),
            if (_batchMode) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('已选 ${_selectedThreadIds.length} 个任务'),
                  TextButton(
                    onPressed: () => _setBatchMode(false),
                    child: const Text('取消'),
                  ),
                  FilledButton.tonal(
                    onPressed:
                        _selectedThreadIds.isEmpty ||
                            (controller.status != RuntimeStatus.ready &&
                                controller.status != RuntimeStatus.running)
                        ? null
                        : () => _archiveSelectedThreads(controller),
                    child: const Text('归档已选'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (controller.threadsLoading && controller.threads.isEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (controller.threadsLoading && controller.threads.isEmpty)
              const SizedBox(height: 6),
            Expanded(
              child: Ink(
                key: const Key('workspace-picker-surface'),
                decoration: BoxDecoration(color: Colors.transparent),
                child: ClipRRect(
                  child: workspaces.isEmpty
                      ? InkWell(
                          key: const Key('sidebar-workspace-empty'),
                          onTap: controller.canCreateWorkspace
                              ? widget.onCreateWorkspace
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final minHeight = constraints.hasBoundedHeight
                                  ? constraints.maxHeight
                                  : 0.0;
                              return SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: minHeight,
                                  ),
                                  child: Center(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        18,
                                        24,
                                        18,
                                        20,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.module,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: palette.border,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: palette.signalSelected,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.folder_open_outlined,
                                              size: 24,
                                              color: palette.signal,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            '从一个工作区开始',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  color: palette.trace,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 7),
                                          Text(
                                            '选择一个项目文件夹，开始运行 Codex 任务。',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: palette.muted,
                                                  height: 1.35,
                                                ),
                                          ),
                                          const SizedBox(height: 18),
                                          SizedBox(
                                            width: double.infinity,
                                            child: FilledButton.icon(
                                              key: const Key(
                                                'sidebar-first-workspace-create-button',
                                              ),
                                              onPressed:
                                                  controller.canCreateWorkspace
                                                  ? widget.onCreateWorkspace
                                                  : null,
                                              icon: const Icon(
                                                Icons.add,
                                                size: 16,
                                              ),
                                              label: const Text('新建第一个工作区'),
                                              style: FilledButton.styleFrom(
                                                minimumSize:
                                                    const Size.fromHeight(36),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : ListView.builder(
                          key: const Key('sidebar-task-list'),
                          controller: _taskListScrollController,
                          primary: false,
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          // Keep the next project node and its first task
                          // mounted even when the footer actions reduce the
                          // visible list height; this preserves immediate
                          // project switching and completion indicators.
                          scrollCacheExtent: const ScrollCacheExtent.pixels(
                            800,
                          ),
                          itemCount: taskListItems.length,
                          itemExtentBuilder: (index, _) =>
                              taskListItems[index].extent,
                          itemBuilder: (context, index) =>
                              taskListItems[index].builder(context),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onConfigureRuntime,
              icon: const Icon(Icons.memory_outlined, size: 16),
              label: const Text('Codex CLI'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.workspacePath == null
                  ? null
                  : widget.onShowGitProject,
              icon: const Icon(Icons.account_tree_outlined, size: 16),
              label: const Text('Git 项目'),
            ),
            const SizedBox(height: 10),
            const MutedText('本地优先 · stdio JSON-RPC'),
            const SizedBox(height: 10),
            Row(
              key: const Key('sidebar-bottom-actions'),
              children: [
                Expanded(
                  child: SidebarMenuAction(
                    key: const Key('sidebar-settings-button'),
                    icon: Icons.settings_outlined,
                    label: 'custom',
                    selected:
                        widget.destination == WorkspaceDestination.settings,
                    onTap: widget.onShowSettings,
                  ),
                ),
                Builder(
                  builder: (buttonContext) => IconButton(
                    key: const Key('sidebar-help-button'),
                    tooltip: '帮助',
                    onPressed: () => _showHelpMenu(buttonContext),
                    icon: const Icon(Icons.help_outline, size: 21),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
