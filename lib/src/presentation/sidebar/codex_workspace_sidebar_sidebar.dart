// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_state.dart';

/// Codex 风格左侧导航栏，承载工作区、任务列表和常用入口。
/// Codex-style left navigation containing workspaces, tasks, and primary actions.
class Sidebar extends StatefulWidget {
  const Sidebar({
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
    required this.onShowPlugins,
    required this.onShowAgents,
    required this.onShowScheduledTasks,
    required this.onShowPullRequests,
    required this.onShowSettings,
    required this.onOpenConversation,
    required this.onNewConversation,
    required this.destination,
    super.key,
  });

  final double width;
  final CodexController controller;
  final VoidCallback onChooseWorkspace;
  final void Function(String primaryPath) onEditWorkspace;
  final VoidCallback onCreateWorkspace;
  final Future<void> Function() onConfigureRuntime;
  final Future<void> Function(CodexThread thread) onRenameThread;
  final Future<void> Function(CodexThread thread) onArchiveThread;
  final Future<ThreadArchiveResult?> Function(List<CodexThread> threads)
  onArchiveThreads;
  final Future<void> Function(CodexThread thread) onDeleteThread;
  final Future<void> Function() onShowArchivedThreads;
  final Future<void> Function() onExportHistory;
  final Future<void> Function() onImportHistory;
  final Future<void> Function() onShowGitProject;
  final Future<void> Function() onShowPlugins;
  final VoidCallback onShowAgents;
  final Future<void> Function() onShowScheduledTasks;
  final Future<void> Function() onShowPullRequests;
  final VoidCallback onShowSettings;
  final VoidCallback onOpenConversation;
  final VoidCallback onNewConversation;
  final WorkspaceDestination destination;

  /// 创建管理侧栏搜索状态的 State 对象。
  /// Creates the State object that manages sidebar search state.
  @override
  State<Sidebar> createState() => SidebarState();
}
