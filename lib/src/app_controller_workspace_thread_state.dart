import 'dart:collection';

import 'package:chatgpt/src/app_controller_thread_view_snapshot.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/services/conversation_history_store_conversation_history_snapshot.dart';
import 'package:chatgpt/src/app_controller_workspace_task_list.dart';

/// 集中维护工作区与线程身份、历史视图和后台归属状态。
/// Owns workspace and thread identity, history views, and background ownership state.
///
/// 控制器仍负责切换流程、历史读写、运行时恢复和通知；本类型只归组这些
/// 流程共享的可变集合，避免状态继续散落在运行时协调代码中。
/// The controller still coordinates switching, history I/O, runtime resume,
/// and notifications; this type only groups the mutable collections shared by
/// those flows.
class CodexWorkspaceThreadState {
  String? workspacePath;
  final List<String> additionalWorkspacePaths = <String>[];
  final List<WorkspaceConfiguration> workspaceConfigurations =
      <WorkspaceConfiguration>[];
  final Set<String> pinnedWorkspacePaths = <String>{};
  final Map<String, WorkspaceTaskList> workspaceTaskLists =
      <String, WorkspaceTaskList>{};
  int workspaceTaskListLoadEpoch = 0;
  String? workspaceProjectId;
  final Set<String> ownedThreadIds = <String>{};
  final Set<String> pinnedThreadIds = <String>{};
  bool threadHistoryInitialized = false;
  final Set<String> legacyWorkspaceHistoryPaths = <String>{};
  final LinkedHashMap<({String workspace, String threadId}), ThreadViewSnapshot>
  threadViewCache = LinkedHashMap();
  final Map<String, List<TimelineEntry>> userMessageEntriesByThreadId =
      <String, List<TimelineEntry>>{};
  final Map<String, ConversationHistorySnapshot> workspaceHistorySnapshots =
      <String, ConversationHistorySnapshot>{};
  final Set<String> runningThreadIds = <String>{};
  final Map<String, String> threadWorkspaceById = <String, String>{};
  final Map<String, String> managedWorktreeIdByThread = <String, String>{};

  String? activeThreadId;
  bool activeThreadAttached = false;
  CodexThread? startupSelectedThread;

  void clearWorkspaceTaskLists() {
    workspaceTaskLists.clear();
    workspaceTaskListLoadEpoch++;
  }

  void clearThreadViewCache() {
    threadViewCache.clear();
    userMessageEntriesByThreadId.clear();
  }

  /// Clears runtime-owned background task bindings without touching workspace
  /// configuration or the currently selected thread.
  void clearRuntimeOwnership() {
    runningThreadIds.clear();
    threadWorkspaceById.clear();
    activeThreadAttached = false;
  }

  void clear() {
    workspacePath = null;
    additionalWorkspacePaths.clear();
    workspaceConfigurations.clear();
    pinnedWorkspacePaths.clear();
    clearWorkspaceTaskLists();
    workspaceProjectId = null;
    ownedThreadIds.clear();
    pinnedThreadIds.clear();
    threadHistoryInitialized = false;
    legacyWorkspaceHistoryPaths.clear();
    clearThreadViewCache();
    workspaceHistorySnapshots.clear();
    clearRuntimeOwnership();
    managedWorktreeIdByThread.clear();
    activeThreadId = null;
    startupSelectedThread = null;
  }
}
