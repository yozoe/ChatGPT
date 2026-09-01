// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_state.dart';

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
