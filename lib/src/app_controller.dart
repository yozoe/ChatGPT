import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/codex_thread.dart';
import 'domain/codex_plugin.dart';
import 'domain/codex_skill.dart';
import 'domain/codex_marketplace.dart';
import 'domain/codex_file_change.dart';
import 'domain/git_project_status.dart';
import 'domain/pending_approval.dart';
import 'domain/runtime_log_entry.dart';
import 'domain/scheduled_task.dart';
import 'domain/task_plan.dart';
import 'domain/timeline_entry.dart';
import 'domain/workspace_configuration.dart';
import 'services/codex_app_server.dart';
import 'services/codex_plugin_store.dart';
import 'services/conversation_history_store.dart';
import 'services/git_project_service.dart';
import 'services/local_session_thread_store.dart';
import 'services/runtime_configuration_store.dart';

enum RuntimeStatus { stopped, starting, ready, running, failed }

enum AuthStatus { checking, signedOut, chatgpt, apiKey, external }

enum ApprovalMode { manual, autoApprove }

/// In-memory view state for a previously opened task.
/// 已打开任务的内存视图缓存。
class _ThreadViewSnapshot {
  const _ThreadViewSnapshot({
    required this.entries,
    required this.fileChanges,
    required this.turnDiff,
  });

  final List<TimelineEntry> entries;
  final List<CodexFileChange> fileChanges;
  final String? turnDiff;
}

/// Read-only local task list for a workspace that is not currently connected.
/// 由本地历史恢复的非当前项目只读任务列表。
@immutable
class WorkspaceTaskList {
  const WorkspaceTaskList({required this.threads, required this.pinnedIds});

  final List<CodexThread> threads;
  final Set<String> pinnedIds;
}

/// 将本地存储的审批模式转换为受支持的安全值。
/// Converts a locally stored approval mode into a supported safe value.
ApprovalMode approvalModeFromStorageValue(String? value) =>
    value == ApprovalMode.autoApprove.name
    ? ApprovalMode.autoApprove
    : ApprovalMode.manual;

/// App Server 公布的推理强度；保留未知字符串以兼容未来新增的模型能力。
/// A reasoning effort advertised by App Server; unknown strings are preserved for future model capabilities.
@immutable
class ReasoningEffort {
  const ReasoningEffort._(this.configValue);

  static const defaultValue = ReasoningEffort._(null);
  static const minimal = ReasoningEffort._('minimal');
  static const low = ReasoningEffort._('low');
  static const medium = ReasoningEffort._('medium');
  static const high = ReasoningEffort._('high');
  static const xhigh = ReasoningEffort._('xhigh');

  /// 要发送给 App Server 的原始配置值；`null` 表示使用模型默认值。
  /// Raw configuration value sent to App Server; `null` uses the model default.
  final String? configValue;

  /// 返回稳定的菜单 Key 名称，同时保留 App Server 的未知值。
  /// Returns a stable menu-key name while preserving unknown App Server values.
  String get name => configValue ?? 'defaultValue';

  /// 返回用于界面的推理强度标签，未知值直接展示原始名称。
  /// Returns a UI label, displaying an unknown effort by its original name.
  String get label => switch (configValue) {
    null => '默认',
    'minimal' => '最小',
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    'max' => '最高',
    final value => value,
  };

  /// 将保存或服务器返回的配置值转换为不会丢失未知值的对象。
  /// Converts a persisted or server-provided value without dropping unknown values.
  static ReasoningEffort fromConfigValue(String? value) {
    final normalized = value?.trim();
    return switch (normalized) {
      null || '' => defaultValue,
      'minimal' => minimal,
      'low' => low,
      'medium' => medium,
      'high' => high,
      'xhigh' => xhigh,
      final value => ReasoningEffort._(value),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ReasoningEffort && other.configValue == configValue;

  @override
  int get hashCode => configValue.hashCode;
}

extension ApprovalModeLabel on ApprovalMode {
  /// 返回用于界面的本地化审批模式标签。
  /// Returns the localized approval-mode label for the UI.
  String get label => switch (this) {
    ApprovalMode.manual => '请求批准',
    ApprovalMode.autoApprove => '帮我批准',
  };
}

/// App Server 模型目录中可供新任务选择的只读条目。
/// A read-only model-catalog entry that can be selected for new App Server threads.
class CodexModelOption {
  const CodexModelOption({
    required this.id,
    required this.displayName,
    required this.description,
    required this.isDefault,
  });

  final String id;
  final String displayName;
  final String description;
  final bool isDefault;
}

/// 提供应用共享的 Codex 控制器，并在 ProviderScope 销毁时释放资源。
/// Provides the app-wide Codex controller and releases its resources when the ProviderScope is disposed.
final codexControllerProvider =
    NotifierProvider<CodexControllerNotifier, CodexController>(
      CodexControllerNotifier.new,
    );

/// 将既有控制器的状态变更桥接为 Riverpod 状态更新。
/// Bridges existing controller changes into Riverpod state updates.
class CodexControllerNotifier extends Notifier<CodexController> {
  late final CodexController _controller;

  @override
  CodexController build() {
    _controller = CodexController();
    _controller.addListener(_publishControllerChange);
    unawaited(_controller.connectRestoredWorkspace());
    ref.onDispose(() {
      _controller.removeListener(_publishControllerChange);
      _controller.dispose();
    });
    return _controller;
  }

  void _publishControllerChange() => state = _controller;

  @override
  bool updateShouldNotify(CodexController previous, CodexController next) =>
      true;
}

class CodexController extends ChangeNotifier {
  CodexController({
    CodexAppServer? server,
    RuntimeConfigurationStore? runtimeConfigurationStore,
    ConversationHistoryStore? conversationHistoryStore,
    LocalSessionThreadStore? localSessionThreadStore,
    CodexPluginStore? pluginStore,
    GitProjectService? gitProjectService,
  }) : _server = server ?? CodexAppServer(),
       _runtimeConfigurationStore =
           runtimeConfigurationStore ??
           testingRuntimeConfigurationStore ??
           RuntimeConfigurationStore(),
       _conversationHistoryStore =
           conversationHistoryStore ??
           testingConversationHistoryStore ??
           ConversationHistoryStore(),
       _localSessionThreadStore =
           localSessionThreadStore ?? LocalSessionThreadStore(),
       _gitProjectService = gitProjectService ?? GitProjectService() {
    _pluginStore =
        pluginStore ??
        CodexPluginStore(executableProvider: _server.resolveExecutable);
    _entries.add(
      _entry(
        TimelineKind.system,
        '欢迎使用 Codex Desk',
        '选择本地项目后启动 Codex App Server。模型、Provider 与凭据由 Codex 配置管理。',
      ),
    );
    _runtimeLoad = _loadRuntimeConfiguration();
    _workspaceLoad = _loadWorkspace();
    _historyLoad = _loadConversationHistory();
  }

  final CodexAppServer _server;

  @visibleForTesting
  static ConversationHistoryStore? testingConversationHistoryStore;
  @visibleForTesting
  static RuntimeConfigurationStore? testingRuntimeConfigurationStore;
  final RuntimeConfigurationStore _runtimeConfigurationStore;
  final ConversationHistoryStore _conversationHistoryStore;
  final LocalSessionThreadStore _localSessionThreadStore;
  final GitProjectService _gitProjectService;
  late final CodexPluginStore _pluginStore;
  StreamSubscription<ServerEvent>? _eventSubscription;
  final List<TimelineEntry> _entries = [];
  final Map<String, CodexFileChange> _fileChangesByPath = {};
  final Set<String> _pinnedThreadIds = {};
  final List<RuntimeLogEntry> _runtimeLogs = [];
  final List<ScheduledTask> _scheduledTasks = [];
  final Map<String, Timer> _scheduledTaskTimers = {};
  final Map<String, int> _agentEntryIndexByItem = {};
  final Set<String> _completedCommandItemIds = {};
  Timer? _deltaNotificationTimer;
  Timer? _historySaveTimer;
  Future<void> _historySave = Future.value();
  // 串行化附加目录快照，保证完成较晚的旧写入不会覆盖新目录集合。
  // Serializes workspace-root snapshots so a slow older write cannot overwrite newer state.
  Future<void> _workspaceRootsSave = Future.value();
  bool _historySaveFailed = false;
  bool _disposed = false;
  bool _startingRuntime = false;
  // Thread history restoration should not be treated as live conversation
  // output by the presentation layer.  The workspace uses this to position
  // the restored timeline without playing a smooth scroll animation.
  bool _resumingThread = false;
  // 每次显式停止、重连或释放都会推进代次，使仍在 await 的旧启动流程失效。
  // Explicit stops, reconnects, and disposal advance this epoch to invalidate stale awaited startup work.
  int _runtimeConnectionEpoch = 0;
  Timer? _runtimeReconnectTimer;
  int _runtimeReconnectAttempt = 0;
  int _threadRefreshEpoch = 0;
  int _threadRefreshRequest = 0;
  int _archivedThreadRefreshRequest = 0;
  final Set<String> _unarchivingThreadIds = {};
  final Set<String> _archivingThreadIds = {};
  final Set<String> _deletingThreadIds = {};
  static const _maximumRuntimeLogEntries = 200;
  static const _maximumThreadViewCacheEntries = 8;
  static const _runtimeReconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];
  Future<void> _reasoningEffortSave = Future.value();
  Future<void> _modelSelectionSave = Future.value();
  Future<void> _approvalModeSave = Future.value();
  Map<String, Set<ReasoningEffort>> _reasoningEffortsByModel = const {};
  String? _catalogDefaultModelId;
  String? _configuredModelId;
  String? _configuredProviderId;
  String? _configuredModelSource;
  String? _configuredProviderSource;
  String? modelCatalogError;
  late final Future<void> _runtimeLoad;
  late final Future<void> _workspaceLoad;
  late final Future<void> _historyLoad;

  RuntimeStatus status = RuntimeStatus.stopped;
  String? workspacePath;
  final List<String> _additionalWorkspacePaths = [];
  final List<WorkspaceConfiguration> _workspaceConfigurations = [];
  final Set<String> _pinnedWorkspacePaths = {};
  final Map<String, WorkspaceTaskList> _workspaceTaskLists = {};
  int _workspaceTaskListLoadEpoch = 0;
  String? _workspaceProjectId;
  final Set<String> _ownedThreadIds = {};
  bool _threadHistoryInitialized = false;
  final Set<String> _legacyWorkspaceHistoryPaths = {};
  final LinkedHashMap<String, _ThreadViewSnapshot> _threadViewCache =
      LinkedHashMap();
  String? activeThreadId;
  // A thread ID restored from local history must be resumed on the new
  // app-server connection before it can receive a turn.
  bool _activeThreadAttached = false;
  String? activeTurnId;
  DateTime? _activeTurnStartedAt;
  String? _activeCommand;
  String? _activeCommandItemId;
  TaskPlan? activeTaskPlan;
  String? lastError;
  PendingApproval? pendingApproval;
  bool approvalResponding = false;
  ApprovalMode approvalMode = ApprovalMode.manual;
  bool _approvalModeChangedBeforeLoad = false;
  ReasoningEffort reasoningEffort = ReasoningEffort.defaultValue;
  List<ReasoningEffort> reasoningEffortOptions = const [
    ReasoningEffort.defaultValue,
  ];
  String? selectedModelId;
  List<CodexModelOption> modelOptions = const [];
  AuthStatus authStatus = AuthStatus.checking;
  String? accountEmail;
  String? accountPlan;
  String? loginUrl;
  bool loginInProgress = false;
  bool requiresOpenaiAuth = false;
  CodexRuntimeProbe? runtimeProbe;
  String? runtimeError;
  bool runtimeChecking = false;
  bool codexConfigurationLoading = false;
  bool codexConfigurationRead = false;
  String? codexConfigurationError;
  List<CodexThread> threads = const [];
  // Keeps the most recent local turn outcome when the server list only reports
  // the thread lifecycle state (for example, `idle` after a failed turn).
  // 当服务端列表只返回线程生命周期状态时，保留最近一次本地 turn 结果。
  final Map<String, String> _localThreadStatuses = {};
  bool threadsLoading = false;
  String? threadsError;
  List<CodexThread> archivedThreads = const [];
  bool archivedThreadsLoading = false;
  String? archivedThreadsError;
  List<CodexPlugin> plugins = const [];
  bool pluginsLoading = false;
  bool pluginSaving = false;
  String? pluginsError;
  String? pluginActionProgress;
  String? pluginActionResult;
  String? pluginActionTargetId;
  bool pluginRuntimeRestartRequired = false;
  List<CodexSkill> skills = const [];
  bool skillsLoading = false;
  String? skillsError;
  List<CodexMarketplace> marketplaces = const [];
  bool marketplacesLoading = false;
  String? marketplacesError;
  GitProjectStatus? gitProjectStatus;
  bool gitProjectLoading = false;
  String? gitProjectError;
  GitProjectChange? gitDiffChange;
  String? gitDiff;
  bool gitDiffLoading = false;
  bool gitDiffTruncated = false;
  bool gitOperationRunning = false;
  String? gitOperationError;

  /// 返回不含主目录且不可由外部修改的附加工作区目录。
  /// Returns additional workspace directories, excluding the primary directory and preventing external mutation.
  List<String> get additionalWorkspacePaths =>
      List.unmodifiable(_additionalWorkspacePaths);

  /// 返回所有已保存工作区；每个工作区独立保留主目录和附加目录。
  /// Returns every saved workspace, each retaining its own primary and additional directories.
  List<WorkspaceConfiguration> get workspaceConfigurations =>
      List.unmodifiable(_workspaceConfigurations);

  /// Returns the locally pinned workspace paths.
  /// 返回本地置顶的工作区路径。
  Set<String> get pinnedWorkspacePaths =>
      Set.unmodifiable(_pinnedWorkspacePaths);

  /// Returns the cached local task list for an inactive workspace.
  /// 返回非当前项目已缓存的本地任务列表。
  WorkspaceTaskList? workspaceTaskListFor(String path) =>
      _workspaceTaskLists[path];

  /// Returns whether a workspace is pinned.
  /// 判断指定工作区是否已置顶。
  bool isWorkspacePinned(String path) => _pinnedWorkspacePaths.contains(path);

  /// Toggles a workspace pin and persists the preference outside the project.
  /// 切换工作区置顶状态，并将偏好保存到项目目录之外。
  Future<void> toggleWorkspacePinned(String path) async {
    if (!_workspaceConfigurations.any(
      (workspace) => workspace.primaryPath == path,
    )) {
      return;
    }
    if (!_pinnedWorkspacePaths.add(path)) {
      _pinnedWorkspacePaths.remove(path);
    }
    try {
      await _runtimeConfigurationStore.savePinnedWorkspaces(
        _pinnedWorkspacePaths,
      );
    } catch (error) {
      lastError = '无法保存项目置顶状态：${_messageOf(error)}';
      _add(TimelineKind.error, '项目置顶保存失败', lastError!);
    }
    if (!_disposed) notifyListeners();
  }

  /// Reads a workspace's cached task count for the hover details card.
  /// 读取工作区本地缓存中的任务数量，供悬停详情卡片显示。
  Future<int> readWorkspaceTaskCount(String path) async {
    final taskList = await readWorkspaceTaskList(path);
    return taskList.threads.length;
  }

  /// Reads a workspace's cached task list without switching the active
  /// runtime. This lets the sidebar keep every project expanded at launch.
  /// 不切换当前运行时地读取项目的本地任务列表，以便侧栏启动时展开全部项目。
  Future<({List<CodexThread> threads, Set<String> pinnedIds})>
  readWorkspaceTaskList(String path) async {
    if (path == workspacePath) {
      return (
        threads: List<CodexThread>.unmodifiable(threads),
        pinnedIds: Set<String>.unmodifiable(_pinnedThreadIds),
      );
    }
    final project = _workspaceConfigurations
        .where((workspace) => workspace.primaryPath == path)
        .firstOrNull;
    var snapshot = await _conversationHistoryStore.read(project?.id ?? path);
    // A configuration upgrade may have written its new project ID before the
    // old path-keyed cache was copied.  A missing ID-keyed snapshot is safe to
    // fall back in that case: newly created projects always save an explicit
    // empty snapshot under their ID.
    if (snapshot == null && project?.id != null) {
      snapshot = await _conversationHistoryStore.read(path);
    }
    return (
      threads: List<CodexThread>.unmodifiable(
        snapshot?.threads ?? const <CodexThread>[],
      ),
      pinnedIds: Set<String>.unmodifiable(
        snapshot?.pinnedThreadIds ?? const <String>{},
      ),
    );
  }

  /// Refreshes local task previews for every inactive workspace. This state is
  /// held by the app-wide controller so Riverpod publishes lifecycle and
  /// asynchronous updates consistently to every sidebar instance.
  Future<void> refreshInactiveWorkspaceTaskLists() async {
    final activePath = workspacePath;
    final workspaces = List<WorkspaceConfiguration>.of(
      _workspaceConfigurations,
    );
    final epoch = ++_workspaceTaskListLoadEpoch;
    final next = <String, WorkspaceTaskList>{};
    for (final workspace in workspaces) {
      if (workspace.primaryPath == activePath) continue;
      try {
        final taskList = await readWorkspaceTaskList(workspace.primaryPath);
        if (_disposed || epoch != _workspaceTaskListLoadEpoch) return;
        next[workspace.primaryPath] = WorkspaceTaskList(
          threads: taskList.threads,
          pinnedIds: taskList.pinnedIds,
        );
      } catch (_) {
        // Leave an unreadable cache out of the sidebar. Selecting the project
        // still reports the detailed persistence error through normal restore.
      }
    }
    if (_disposed || epoch != _workspaceTaskListLoadEpoch) return;
    _workspaceTaskLists
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// 返回传给新任务的完整工作区根目录，主目录始终位于第一项。
  /// Returns all workspace roots passed to new tasks, always placing the primary directory first.
  List<String> get workspaceRoots => [
    ?workspacePath,
    ..._additionalWorkspacePaths,
  ];

  /// 返回不可修改的当前时间线副本视图。
  /// Returns an unmodifiable view of the current timeline.
  List<TimelineEntry> get entries => List.unmodifiable(_entries);

  /// 是否正在加载切换后任务的历史记录。
  /// Whether the selected thread's history is currently being restored.
  bool get isResumingThread => _resumingThread;

  /// Whether the currently selected task already has an in-memory view cache.
  /// 当前选中任务是否已有内存视图缓存。
  bool get hasCachedActiveThreadView =>
      activeThreadId != null && _threadViewCache.containsKey(activeThreadId);

  /// Thread IDs with a retained in-memory page snapshot for this workspace.
  /// 当前项目中已保留内存页面快照的任务 ID。
  Set<String> get cachedThreadViewIds =>
      Set.unmodifiable(_threadViewCache.keys);

  /// 返回不可修改的已记录文件变更视图。
  /// Returns an unmodifiable view of recorded file changes.
  List<CodexFileChange> get fileChanges =>
      List.unmodifiable(_fileChangesByPath.values);
  String? turnDiff;

  /// 返回最近的已脱敏运行时日志；日志仅保留在本次应用进程的内存中。
  /// Returns recent redacted runtime logs; logs are retained only in this app process's memory.
  List<RuntimeLogEntry> get runtimeLogs => List.unmodifiable(_runtimeLogs);

  /// Scheduled prompts are local to Codex Desk and remain queued across app
  /// restarts. They execute only while this desktop app is running.
  List<ScheduledTask> get scheduledTasks => List.unmodifiable(_scheduledTasks);

  /// 返回当前项目中被置顶的任务 ID，不允许外部修改集合。
  /// Returns pinned task IDs for the current workspace as an immutable set.
  Set<String> get pinnedThreadIds => Set.unmodifiable(_pinnedThreadIds);

  /// Stable identity of the active project, independent of its source path.
  String? get workspaceProjectId => _workspaceProjectId;

  /// 判断指定任务是否已在当前项目中置顶。
  /// Returns whether a task is pinned in the current workspace.
  bool isThreadPinned(String threadId) => _pinnedThreadIds.contains(threadId);

  /// 从当前项目读取只读 Git 工作区摘要；不会执行任何改变 Git 状态的命令。
  /// Reads a read-only Git working-tree summary for the current project without executing state-changing Git commands.
  Future<void> refreshGitProject() async {
    final workspace = workspacePath;
    if (workspace == null) return;
    gitProjectLoading = true;
    gitProjectError = null;
    if (!_disposed) notifyListeners();
    try {
      final next = await _gitProjectService.inspect(workspace);
      if (_disposed || workspacePath != workspace) return;
      gitProjectStatus = next;
      gitProjectError = next.error;
    } catch (error) {
      if (_disposed || workspacePath != workspace) return;
      gitProjectError = _messageOf(error);
    } finally {
      if (!_disposed && workspacePath == workspace) {
        gitProjectLoading = false;
        notifyListeners();
      }
    }
  }

  /// 读取当前项目中指定 Git 改动的只读 Diff；不会暂存、还原或修改文件。
  /// Reads a read-only diff for a selected Git change without staging, restoring, or modifying files.
  Future<void> showGitDiff(GitProjectChange change) async {
    final workspace = workspacePath;
    if (workspace == null) return;
    gitDiffLoading = true;
    gitDiffChange = change;
    gitDiff = null;
    gitDiffTruncated = false;
    if (!_disposed) notifyListeners();
    try {
      final next = await _gitProjectService.readDiffPreview(
        workspace: workspace,
        change: change,
      );
      if (_disposed || workspacePath != workspace || gitDiffChange != change) {
        return;
      }
      gitDiff = next.content;
      gitDiffTruncated = next.truncated;
    } catch (error) {
      if (_disposed || workspacePath != workspace || gitDiffChange != change) {
        return;
      }
      gitDiff = '无法读取 Git Diff：${_messageOf(error)}';
      gitDiffTruncated = false;
    } finally {
      if (!_disposed && workspacePath == workspace && gitDiffChange == change) {
        gitDiffLoading = false;
        notifyListeners();
      }
    }
  }

  /// 暂存一个文件，然后刷新当前工作区的 Git 摘要。
  /// Stages one file and then refreshes the active workspace's Git summary.
  Future<bool> stageGitChange(GitProjectChange change) => _runGitOperation(
    () =>
        _gitProjectService.stageFile(workspace: workspacePath!, change: change),
  );

  /// 在用户确认后还原一个文件，然后刷新 Git 摘要。
  /// Restores one file after user confirmation and then refreshes the Git summary.
  Future<bool> revertGitChange(GitProjectChange change) => _runGitOperation(
    () => _gitProjectService.revertFile(
      workspace: workspacePath!,
      change: change,
    ),
  );

  /// 以用户输入的消息创建 Git 提交；不会隐式暂存文件。
  /// Creates a Git commit with the user's message and never stages files implicitly.
  Future<bool> commitGitChanges(String message) => _runGitOperation(
    () =>
        _gitProjectService.commit(workspace: workspacePath!, message: message),
  );

  /// 推送当前 Git 分支，Git 会使用已配置的上游和凭据。
  /// Pushes the current Git branch using its configured upstream and credentials.
  Future<bool> pushGitBranch() => _runGitOperation(
    () => _gitProjectService.push(workspace: workspacePath!),
  );

  /// 使用本机已认证的 GitHub CLI 为当前分支创建拉取请求。
  /// Creates a pull request for the current branch with the locally authenticated GitHub CLI.
  Future<bool> createGitPullRequest(String title) => _runGitOperation(
    () => _gitProjectService.createPullRequest(
      workspace: workspacePath!,
      title: title,
    ),
  );

  Future<bool> _runGitOperation(Future<void> Function() operation) async {
    if (workspacePath == null || gitOperationRunning) return false;
    gitOperationRunning = true;
    gitOperationError = null;
    if (!_disposed) notifyListeners();
    try {
      await operation();
      await refreshGitProject();
      return true;
    } catch (error) {
      gitOperationError = _messageOf(error);
      return false;
    } finally {
      gitOperationRunning = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 清除当前内存中的运行时诊断日志，不影响历史对话、项目文件或 Codex 配置。
  /// Clears in-memory runtime diagnostic logs without affecting history, project files, or Codex configuration.
  void clearRuntimeLogs() {
    if (_runtimeLogs.isEmpty) return;
    _runtimeLogs.clear();
    if (!_disposed) notifyListeners();
  }

  /// 生成可复制的脱敏运行时诊断报告，用于排查本机 CLI、工作区和最近日志问题。
  /// Builds a copyable redacted runtime diagnostic report for local CLI, workspace, and recent-log troubleshooting.
  String buildRuntimeDiagnosticReport() {
    final probe = runtimeProbe;
    final lines = <String>[
      'Codex Desk runtime diagnostics',
      'Generated: ${DateTime.now().toIso8601String()}',
      'Runtime status: ${status.name}',
      'App Server running: ${_server.isRunning ? 'yes' : 'no'}',
      'Workspace selected: ${workspacePath == null ? 'no' : 'yes'}',
      'Configured CLI: ${CodexAppServer.redactDiagnosticText(_server.executable)}',
      'CLI available: ${probe?.isAvailable == true ? 'yes' : 'no'}',
      if (probe?.discovery?.isNotEmpty == true)
        'CLI discovery: ${probe!.discovery}',
      if (probe?.executablePath?.isNotEmpty == true)
        'Resolved CLI: ${CodexAppServer.redactDiagnosticText(probe!.executablePath!)}',
      if (probe?.version?.isNotEmpty == true)
        'CLI version: ${CodexAppServer.redactDiagnosticText(probe!.version!)}',
      if (probe?.error?.isNotEmpty == true)
        'CLI error: ${CodexAppServer.redactDiagnosticText(probe!.error!)}',
      'CODEX_HOME configured: ${Platform.environment['CODEX_HOME']?.isNotEmpty == true ? 'yes' : 'no'}',
      'Provider: $providerLabel',
      'Authentication: $authLabel',
      if (lastError?.isNotEmpty == true)
        'Last error: ${CodexAppServer.redactDiagnosticText(lastError!)}',
      '',
      'Recent runtime logs (${_runtimeLogs.length}/$_maximumRuntimeLogEntries):',
      if (_runtimeLogs.isEmpty) '(none)',
      ..._runtimeLogs.map((entry) => entry.toDiagnosticLine()),
    ];
    return lines.join('\n');
  }

  /// 指示当前状态是否允许发送新任务。
  /// Indicates whether the current state permits sending a new task.
  bool get canSend =>
      status == RuntimeStatus.ready &&
      workspacePath != null &&
      (activeThreadId == null || _activeThreadAttached) &&
      _hasUsableModelSelection &&
      _hasUsableReasoningEffort &&
      (!requiresOpenaiAuth || authStatus != AuthStatus.signedOut);

  /// 指示是否可以清空当前任务并开始一个新任务。
  /// Indicates whether the current task can be cleared to start a new task.
  bool get canCreateThread =>
      status == RuntimeStatus.ready && workspacePath != null;

  /// 指示当前正在运行的任务是否可以中断。
  /// Indicates whether the running task can be interrupted.
  bool get canStop => status == RuntimeStatus.running && activeThreadId != null;

  /// Indicates whether the active turn can accept a direction adjustment.
  /// 当前运行中的 turn 只有在已收到 turn id 时才能调整方向。
  bool get canSteer =>
      status == RuntimeStatus.running &&
      activeThreadId != null &&
      activeTurnId != null;

  /// 当前 turn 中正执行的命令；命令完成后立即清除，不写入持久化状态。
  /// The command currently running in this turn. It is cleared on completion
  /// and is deliberately not persisted.
  String? get activeCommand => _activeCommand;

  /// 指示当前是否可以安全切换本地项目。
  /// Indicates whether it is safe to switch the local workspace.
  bool get canChooseWorkspace =>
      status == RuntimeStatus.stopped ||
      (status == RuntimeStatus.failed && !_server.isRunning);

  /// 指示当前任务状态是否允许新建或切换工作区并重建运行时连接。
  /// Indicates whether the current task state permits creating or switching workspaces and rebuilding the runtime connection.
  bool get canChangePrimaryWorkspace =>
      !_startingRuntime &&
      status != RuntimeStatus.starting &&
      status != RuntimeStatus.running;

  /// 指示本地 App Server 是否可以停止。
  /// Indicates whether the local App Server can be stopped.
  bool get canStopRuntime =>
      _server.isRunning ||
      status == RuntimeStatus.ready ||
      status == RuntimeStatus.running;

  /// 指示当前待处理审批是否可以提交答复。
  /// Indicates whether the pending approval can be answered.
  bool get canRespondToApproval =>
      pendingApproval != null && !approvalResponding;

  /// 返回线程是否正在恢复归档，供界面防止重复提交。
  /// Returns whether a thread is being unarchived to prevent duplicate UI actions.
  bool isUnarchivingThread(String threadId) =>
      _unarchivingThreadIds.contains(threadId);

  /// 返回当前认证状态的本地化展示文本。
  /// Returns localized display text for the current authentication state.
  String get authLabel => switch (authStatus) {
    AuthStatus.checking => '检查账户',
    AuthStatus.signedOut => '未登录',
    AuthStatus.chatgpt =>
      accountPlan == null ? 'ChatGPT' : 'ChatGPT $accountPlan',
    AuthStatus.apiKey => 'API Key',
    AuthStatus.external => '外部 Provider',
  };

  /// 返回由 App Server 从最终生效配置中解析出的 Provider。
  /// Returns the provider resolved by App Server from the effective configuration.
  String get providerLabel =>
      _configuredProviderId ??
      (codexConfigurationRead ? 'openai（默认）' : 'Codex 配置');

  /// 返回最终生效配置中的模型；未显式配置时显示 Codex 模型目录的默认值。
  /// Returns the effective configured model, falling back to Codex's model-catalog default when it is not explicitly configured.
  String get configuredModelLabel =>
      _configuredModelId ??
      _catalogDefaultModelId ??
      (codexConfigurationRead ? '未显式配置（使用 Codex 默认模型）' : '等待读取运行时配置');

  /// 返回模型选择器当前显示的值；`null` 表示跟随最终生效的 Codex 配置。
  /// Returns the current model-picker value; `null` means follow the effective Codex configuration.
  String get selectedModelLabel {
    final selected = selectedModelId;
    if (selected == null) return '跟随配置';
    for (final option in modelOptions) {
      if (option.id == selected) return option.displayName;
    }
    return selected;
  }

  /// 返回后续新建任务实际将使用的模型标签。
  /// Returns the model label that subsequent new tasks will use.
  String get newTaskModelLabel {
    final selected = selectedModelId;
    if (selected == null) return configuredModelLabel;
    for (final option in modelOptions) {
      if (option.id == selected) return option.displayName;
    }
    return selected;
  }

  /// 指示模型选择器是否有目录选项，或需要允许用户清除失效的已保存选择。
  /// Indicates whether catalog options exist or an unresolved saved selection must remain clearable.
  bool get canSelectModel => modelOptions.isNotEmpty || selectedModelId != null;

  /// 指示推理强度选择器是否有能力选项，或需要允许用户恢复为默认值。
  /// Indicates whether capability options exist or a saved effort must remain resettable.
  bool get canSelectReasoningEffort =>
      reasoningEffortOptions.length > 1 ||
      reasoningEffort != ReasoningEffort.defaultValue;

  /// 返回模型目录失败造成的当前选择错误；安全的“跟随配置 + 默认强度”不受影响。
  /// Returns a selection error caused by catalog failure; safe config-following defaults remain usable.
  String? get modelSelectionError {
    if (_hasUsableModelSelection && _hasUsableReasoningEffort) return null;
    return modelCatalogError ?? '所选模型或推理强度当前不可用。';
  }

  bool get _hasUsableModelSelection {
    final selected = selectedModelId;
    return selected == null ||
        modelOptions.any((option) => option.id == selected);
  }

  bool get _hasUsableReasoningEffort =>
      reasoningEffort == ReasoningEffort.defaultValue ||
      _supportsReasoningEffort(_newThreadModelId, reasoningEffort);

  /// 返回模型配置的来源；未显式配置时说明使用 Codex 默认值。
  /// Returns the model configuration source, or explains that Codex's default is used.
  String get configuredModelSourceLabel =>
      _configuredModelSource ??
      (_configuredModelId == null && codexConfigurationRead
          ? 'Codex 内置默认值'
          : '尚未读取');

  /// 返回 Provider 配置的来源；未显式配置时说明使用内置 OpenAI Provider。
  /// Returns the provider configuration source, or explains that the built-in OpenAI provider is used.
  String get configuredProviderSourceLabel =>
      _configuredProviderSource ??
      (_configuredProviderId == null && codexConfigurationRead
          ? 'Codex 内置默认值'
          : '尚未读取');

  /// 返回只读配置读取状态，实际连通性仍需成功请求确认。
  /// Returns the read-only configuration status; actual connectivity still requires a successful request.
  String get codexConfigurationStatusLabel {
    if (codexConfigurationLoading) return '正在从 Codex 运行时读取…';
    if (codexConfigurationError != null) return '读取失败';
    if (codexConfigurationRead) return '已从 Codex 运行时读取';
    return '运行时启动后读取';
  }

  /// 返回当前 Codex 用户级配置文件的常规路径；项目配置仍由 App Server 合并。
  /// Returns the conventional user config path; App Server still merges project configuration.
  String get codexUserConfigPath {
    final codexHome = Platform.environment['CODEX_HOME']?.trim();
    if (codexHome != null && codexHome.isNotEmpty) {
      return '$codexHome/config.toml';
    }
    final home = Platform.environment['HOME']?.trim();
    return home == null || home.isEmpty
        ? '~/.codex/config.toml'
        : '$home/.codex/config.toml';
  }

  /// 让 App Server 按当前项目重新解析配置，并只保留用于展示的非敏感字段。
  /// Asks App Server to resolve configuration for the current workspace and retains only non-sensitive display fields.
  Future<void> refreshCodexConfiguration({bool notify = true}) async {
    if (!_server.isRunning) return;
    codexConfigurationLoading = true;
    codexConfigurationError = null;
    if (notify && !_disposed) notifyListeners();
    try {
      final result = await _server.readConfig(workingDirectory: workspacePath);
      final config = JsonMap.from(result['config'] as Map);
      final origins = result['origins'];
      _configuredModelId = _nonEmptyConfigString(
        config['model'] ?? config['modelId'],
      );
      _configuredProviderId = _nonEmptyConfigString(
        config['model_provider'] ?? config['modelProvider'],
      );
      _configuredModelSource = _configurationOriginLabel(origins, 'model');
      _configuredProviderSource = _configurationOriginLabel(
        origins,
        'model_provider',
      );
      codexConfigurationRead = true;
    } catch (error) {
      _configuredModelId = null;
      _configuredProviderId = null;
      _configuredModelSource = null;
      _configuredProviderSource = null;
      codexConfigurationRead = false;
      codexConfigurationError = _messageOf(error);
    } finally {
      codexConfigurationLoading = false;
      if (notify && !_disposed) notifyListeners();
    }
  }

  /// 清除只属于已停止 App Server 的配置与模型快照，同时保留用户偏好。
  /// Clears configuration and model snapshots owned by a stopped App Server while retaining user preferences.
  void _clearRuntimeResolvedConfiguration() {
    _configuredModelId = null;
    _configuredProviderId = null;
    _configuredModelSource = null;
    _configuredProviderSource = null;
    codexConfigurationLoading = false;
    codexConfigurationRead = false;
    codexConfigurationError = null;
    _reasoningEffortsByModel = const {};
    _catalogDefaultModelId = null;
    modelOptions = const [];
    modelCatalogError = null;
    reasoningEffortOptions = [
      ReasoningEffort.defaultValue,
      if (reasoningEffort != ReasoningEffort.defaultValue) reasoningEffort,
    ];
  }

  /// 指示运行时路径是否可以在不影响会话的情况下配置。
  /// Indicates whether the runtime path can be configured without disrupting a session.
  bool get canConfigureRuntime =>
      !_startingRuntime &&
      status != RuntimeStatus.starting &&
      status != RuntimeStatus.running;

  /// 验证、切换并持久化本地项目，同时恢复该项目的本地历史。
  /// Validates, selects, and persists a local workspace, then restores its local history.
  Future<void> selectWorkspace(String path) async {
    if (!canChooseWorkspace) {
      lastError = '请先停止当前运行时，再切换项目。';
      _add(TimelineKind.error, '无法切换项目', lastError!);
      notifyListeners();
      return;
    }
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final directory = Directory(normalized);
    if (!await directory.exists()) {
      lastError = '该项目目录不存在：$normalized';
      _add(TimelineKind.error, '无法选择项目', lastError!);
      notifyListeners();
      return;
    }
    final canonicalPath = await directory.resolveSymbolicLinks();
    if (await _isSystemTemporaryDirectory(canonicalPath)) {
      lastError = '系统临时目录不能作为项目，请选择实际项目文件夹。';
      _add(TimelineKind.error, '无法选择项目', lastError!);
      notifyListeners();
      return;
    }
    await _saveConversationHistory();
    _updateCurrentWorkspaceConfiguration();
    final existingIndex = _workspaceConfigurations.indexWhere(
      (configuration) => configuration.primaryPath == canonicalPath,
    );
    final nextAdditionalPaths = existingIndex < 0
        ? const <String>[]
        : _workspaceConfigurations[existingIndex].additionalPaths;
    if (existingIndex < 0) {
      _workspaceConfigurations.add(
        WorkspaceConfiguration(
          id: _newWorkspaceProjectId(),
          primaryPath: canonicalPath,
        ),
      );
    }
    _invalidateThreadRefreshes();
    workspacePath = canonicalPath;
    _workspaceProjectId = existingIndex < 0
        ? _workspaceConfigurations.last.id
        : _workspaceConfigurations[existingIndex].id;
    _additionalWorkspacePaths
      ..clear()
      ..addAll(nextAdditionalPaths.where((path) => path != canonicalPath));
    _updateCurrentWorkspaceConfiguration();
    _clearRuntimeResolvedConfiguration();
    _threadViewCache.clear();
    activeThreadId = null;
    _activeThreadAttached = false;
    threads = const [];
    archivedThreads = const [];
    _pinnedThreadIds.clear();
    _localThreadStatuses.clear();
    gitProjectStatus = null;
    gitProjectError = null;
    gitDiffChange = null;
    gitDiff = null;
    gitDiffLoading = false;
    gitDiffTruncated = false;
    _clearStreamingState();
    _clearFileChanges();
    _resetConversationTimeline();
    if (existingIndex < 0) {
      // A newly created project starts with an explicit empty ownership set,
      // even when Codex has older sessions for the same source directory.
      _threadHistoryInitialized = true;
      _ownedThreadIds.clear();
      await _saveConversationHistory();
    } else {
      await _restoreConversationHistory(canonicalPath);
    }
    unawaited(refreshGitProject());
    unawaited(refreshInactiveWorkspaceTaskLists());
    _add(TimelineKind.system, '项目已选择', canonicalPath);
    notifyListeners();
    try {
      await _runtimeConfigurationStore.saveWorkspace(canonicalPath);
      await _saveAdditionalWorkspacePaths();
    } catch (error) {
      _add(TimelineKind.error, '无法保存项目选择', _messageOf(error));
      if (!_disposed) notifyListeners();
    }
  }

  /// 创建或切换工作区并自动重建运行时连接；正在执行任务时保持原工作区不变。
  /// Creates or switches workspaces and automatically rebuilds the runtime connection, preserving the active workspace during a task.
  Future<bool> selectWorkspaceAndReconnect(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return false;
    final directory = Directory(normalized);
    if (!await directory.exists()) {
      lastError = '该项目目录不存在：$normalized';
      _add(TimelineKind.error, '无法选择项目', lastError!);
      notifyListeners();
      return false;
    }
    final canonicalPath = await directory.resolveSymbolicLinks();
    if (await _isSystemTemporaryDirectory(canonicalPath)) {
      lastError = '系统临时目录不能作为项目，请选择实际项目文件夹。';
      _add(TimelineKind.error, '无法选择项目', lastError!);
      notifyListeners();
      return false;
    }
    if (canonicalPath == workspacePath) {
      _updateCurrentWorkspaceConfiguration();
      try {
        await _runtimeConfigurationStore.saveWorkspace(canonicalPath);
        await _saveAdditionalWorkspacePaths();
      } catch (error) {
        _add(TimelineKind.error, '无法保存工作区', _messageOf(error));
        if (!_disposed) notifyListeners();
      }
      if (status == RuntimeStatus.stopped || status == RuntimeStatus.failed) {
        await startRuntime();
      }
      return true;
    }
    if (!canChangePrimaryWorkspace) {
      lastError = status == RuntimeStatus.running
          ? '请等待当前任务完成后再新建或切换工作区。'
          : '运行时正在自动连接，请稍后再新建或切换工作区。';
      _add(TimelineKind.error, '无法切换工作区', lastError!);
      notifyListeners();
      return false;
    }

    if (_server.isRunning || status == RuntimeStatus.ready) {
      await stopRuntime();
      if (_server.isRunning) return false;
    }
    await selectWorkspace(canonicalPath);
    if (workspacePath != canonicalPath || _disposed) return false;
    await startRuntime();
    return true;
  }

  /// Switches to a task's owning workspace before resuming it. Cached task
  /// previews from other projects must never be resumed on the current
  /// project's runtime connection.
  Future<void> openWorkspaceThread({
    required String workspace,
    required CodexThread thread,
  }) async {
    if (workspace != workspacePath) {
      final switched = await selectWorkspaceAndReconnect(workspace);
      if (!switched || workspacePath != workspace || _disposed) return;
    }
    await resumeThread(thread);
  }

  /// 用所选主目录创建并打开工作区；已保存目录会直接切换，不会生成重复记录。
  /// Creates and opens a workspace from a primary directory, switching to an existing saved entry without duplication.
  Future<bool> createWorkspace(String path) =>
      selectWorkspaceAndReconnect(path);

  /// 从工作区列表移除一个非当前记录；只删除本地偏好，不删除目录或历史缓存。
  /// Removes a non-active workspace record from local preferences without deleting directories or cached history.
  Future<void> forgetWorkspace(String primaryPath) async {
    if (primaryPath == workspacePath) {
      lastError = '不能移除当前工作区，请先切换到其他工作区。';
      notifyListeners();
      return;
    }
    final previousLength = _workspaceConfigurations.length;
    _workspaceConfigurations.removeWhere(
      (configuration) => configuration.primaryPath == primaryPath,
    );
    _workspaceTaskLists.remove(primaryPath);
    _workspaceTaskListLoadEpoch++;
    if (_workspaceConfigurations.length == previousLength) return;
    final wasPinned = _pinnedWorkspacePaths.remove(primaryPath);
    _add(TimelineKind.system, '已移除工作区记录', primaryPath);
    notifyListeners();
    try {
      await _saveAdditionalWorkspacePaths();
      if (wasPinned) {
        await _runtimeConfigurationStore.savePinnedWorkspaces(
          _pinnedWorkspacePaths,
        );
      }
    } catch (error) {
      _add(TimelineKind.error, '无法保存工作区列表', _messageOf(error));
      if (!_disposed) notifyListeners();
    }
  }

  /// 更新工作区显示名称并持久化；名称为空时恢复为主目录名称。
  /// Renames a workspace label and persists it; an empty name restores the directory name.
  Future<void> renameWorkspace(String primaryPath, String name) async {
    final index = _workspaceConfigurations.indexWhere(
      (configuration) => configuration.primaryPath == primaryPath,
    );
    if (index < 0) return;
    final trimmed = name.trim();
    final current = _workspaceConfigurations[index];
    _workspaceConfigurations[index] = WorkspaceConfiguration(
      id: current.id,
      primaryPath: current.primaryPath,
      additionalPaths: current.additionalPaths,
      name: trimmed.isEmpty ? null : trimmed,
    );
    notifyListeners();
    try {
      await _saveAdditionalWorkspacePaths();
    } catch (error) {
      lastError = '无法保存项目名称：${_messageOf(error)}';
      if (!_disposed) notifyListeners();
    }
  }

  /// 移除当前项目记录并清空活动工作区，不删除磁盘目录或历史缓存文件。
  /// Removes the current project record and clears the active workspace without deleting its directory or history.
  Future<bool> removeCurrentWorkspace() async {
    final primary = workspacePath;
    if (primary == null || !canChangePrimaryWorkspace) return false;
    await stopRuntime();
    _workspaceConfigurations.removeWhere(
      (configuration) => configuration.primaryPath == primary,
    );
    _pinnedWorkspacePaths.remove(primary);
    _threadViewCache.clear();
    workspacePath = null;
    _additionalWorkspacePaths.clear();
    activeThreadId = null;
    _activeThreadAttached = false;
    threads = const [];
    archivedThreads = const [];
    _resetConversationTimeline();
    _clearFileChanges();
    _clearStreamingState();
    _add(TimelineKind.system, '已移除本地项目', primary);
    notifyListeners();
    try {
      await _runtimeConfigurationStore.clearWorkspace();
      await _runtimeConfigurationStore.saveWorkspaces(_workspaceConfigurations);
      await _runtimeConfigurationStore.saveAdditionalWorkspaces(const []);
      await _runtimeConfigurationStore.savePinnedWorkspaces(
        _pinnedWorkspacePaths,
      );
    } catch (error) {
      lastError = '无法保存项目移除状态：${_messageOf(error)}';
      if (!_disposed) notifyListeners();
    }
    return true;
  }

  /// 验证并添加一个供后续新任务访问的附加工作区目录；首个目录会成为主目录。
  /// Validates and adds an additional workspace directory for future tasks; the first directory becomes primary.
  Future<void> addWorkspaceRoot(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final directory = Directory(normalized);
    if (!await directory.exists()) {
      lastError = '该目录不存在：$normalized';
      _add(TimelineKind.error, '无法添加目录', lastError!);
      notifyListeners();
      return;
    }
    final canonicalPath = await directory.resolveSymbolicLinks();
    if (await _isSystemTemporaryDirectory(canonicalPath)) {
      lastError = '系统临时目录不能作为工作区目录。';
      _add(TimelineKind.error, '无法添加目录', lastError!);
      notifyListeners();
      return;
    }
    if (workspacePath == null) {
      await selectWorkspace(canonicalPath);
      return;
    }
    if (canonicalPath == workspacePath ||
        _additionalWorkspacePaths.contains(canonicalPath)) {
      return;
    }
    _additionalWorkspacePaths.add(canonicalPath);
    lastError = null;
    _add(TimelineKind.system, '已添加工作区目录', canonicalPath);
    notifyListeners();
    try {
      await _saveAdditionalWorkspacePaths();
    } catch (error) {
      _add(TimelineKind.error, '无法保存附加目录', _messageOf(error));
      if (!_disposed) notifyListeners();
    }
  }

  /// 为指定工作区添加一个附加源文件夹；编辑非当前项目时也可安全使用。
  /// Adds an additional source folder to a specified workspace, including when editing an inactive project.
  Future<void> addWorkspaceRootToWorkspace(
    String primaryPath,
    String path,
  ) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final directory = Directory(normalized);
    if (!await directory.exists()) {
      lastError = '该目录不存在：$normalized';
      notifyListeners();
      return;
    }
    final canonicalPath = await directory.resolveSymbolicLinks();
    if (await _isSystemTemporaryDirectory(canonicalPath)) {
      lastError = '系统临时目录不能作为工作区目录。';
      notifyListeners();
      return;
    }
    final index = _workspaceConfigurations.indexWhere(
      (configuration) => configuration.primaryPath == primaryPath,
    );
    if (index < 0) return;
    final configuration = _workspaceConfigurations[index];
    if (canonicalPath == primaryPath ||
        configuration.additionalPaths.contains(canonicalPath)) {
      return;
    }
    _workspaceConfigurations[index] = WorkspaceConfiguration(
      id: configuration.id,
      primaryPath: configuration.primaryPath,
      additionalPaths: [...configuration.additionalPaths, canonicalPath],
      name: configuration.name,
    );
    if (primaryPath == workspacePath) {
      _additionalWorkspacePaths.add(canonicalPath);
    }
    _add(TimelineKind.system, '已添加工作区目录', canonicalPath);
    notifyListeners();
    await _saveAdditionalWorkspacePaths();
  }

  /// 删除当前工作区的一个附加目录；主目录由工作区记录确定。
  /// Removes an additional directory from the current workspace; its saved entry determines the primary directory.
  Future<void> removeWorkspaceRoot(String path) async {
    if (!_additionalWorkspacePaths.remove(path)) return;
    lastError = null;
    _add(TimelineKind.system, '已移除工作区目录', path);
    notifyListeners();
    try {
      await _saveAdditionalWorkspacePaths();
    } catch (error) {
      _add(TimelineKind.error, '无法保存附加目录', _messageOf(error));
      if (!_disposed) notifyListeners();
    }
  }

  /// 从指定工作区移除附加源文件夹；不会删除磁盘目录。
  /// Removes an additional source folder from a specified workspace without deleting its directory.
  Future<void> removeWorkspaceRootFromWorkspace(
    String primaryPath,
    String path,
  ) async {
    if (primaryPath == workspacePath) {
      await removeWorkspaceRoot(path);
      return;
    }
    final index = _workspaceConfigurations.indexWhere(
      (configuration) => configuration.primaryPath == primaryPath,
    );
    if (index < 0) return;
    final configuration = _workspaceConfigurations[index];
    if (!configuration.additionalPaths.contains(path)) return;
    _workspaceConfigurations[index] = WorkspaceConfiguration(
      id: configuration.id,
      primaryPath: configuration.primaryPath,
      additionalPaths: configuration.additionalPaths
          .where((candidate) => candidate != path)
          .toList(growable: false),
      name: configuration.name,
    );
    _add(TimelineKind.system, '已移除工作区目录', path);
    notifyListeners();
    await _saveAdditionalWorkspacePaths();
  }

  /// 清空当前任务状态，使下一条消息创建新的服务器线程。
  /// Clears the current task state so the next message creates a server thread.
  void createThread() {
    if (!canCreateThread) {
      lastError = status == RuntimeStatus.running
          ? '当前任务运行中；完成或停止后才能新建任务。'
          : '运行时就绪后才能新建任务。';
      notifyListeners();
      return;
    }
    activeThreadId = null;
    _activeThreadAttached = false;
    _clearStreamingState();
    _clearFileChanges();
    _resetConversationTimeline();
    _add(TimelineKind.system, '已新建任务', '发送第一条消息后会创建新的 Thread。');
    notifyListeners();
  }

  /// Queues a prompt for the current project. The task reconnects to its saved
  /// project before it sends, so changing projects meanwhile is safe.
  Future<bool> schedulePrompt({
    required String prompt,
    required DateTime runAt,
  }) async {
    await _runtimeLoad;
    final text = prompt.trim();
    final workspace = workspacePath;
    if (text.isEmpty || workspace == null || !runAt.isAfter(DateTime.now())) {
      return false;
    }
    final task = ScheduledTask(
      id: '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}',
      workspacePath: workspace,
      prompt: text,
      runAt: runAt,
    );
    _scheduledTasks.add(task);
    _scheduledTasks.sort((left, right) => left.runAt.compareTo(right.runAt));
    _armScheduledTask(task);
    try {
      await _saveScheduledTasks();
    } catch (error) {
      _scheduledTasks.removeWhere((value) => value.id == task.id);
      _scheduledTaskTimers.remove(task.id)?.cancel();
      lastError = '无法保存已安排任务：${_messageOf(error)}';
      _add(TimelineKind.error, '已安排任务保存失败', lastError!);
      notifyListeners();
      return false;
    }
    _add(TimelineKind.system, '已安排任务', '将在 ${task.runAt} 发送到项目 $workspace。');
    notifyListeners();
    return true;
  }

  /// Removes an unsent scheduled prompt without changing any project files.
  Future<void> cancelScheduledTask(String id) async {
    await _runtimeLoad;
    final removed = _scheduledTasks.where((task) => task.id == id).firstOrNull;
    if (removed == null) return;
    _scheduledTasks.remove(removed);
    _scheduledTaskTimers.remove(id)?.cancel();
    try {
      await _saveScheduledTasks();
    } catch (error) {
      _scheduledTasks.add(removed);
      _scheduledTasks.sort((left, right) => left.runAt.compareTo(right.runAt));
      _armScheduledTask(removed);
      lastError = '无法取消已安排任务：${_messageOf(error)}';
      _add(TimelineKind.error, '取消已安排任务失败', lastError!);
    }
    if (!_disposed) notifyListeners();
  }

  /// 启动、初始化本地 App Server，并加载账户与线程状态。
  /// Starts and initializes the local App Server, then loads account and thread state.
  Future<void> startRuntime() async {
    final workspace = workspacePath;
    if (workspace == null) {
      lastError = '请先选择一个本地项目目录。';
      notifyListeners();
      return;
    }
    if (_startingRuntime ||
        status == RuntimeStatus.starting ||
        status == RuntimeStatus.ready ||
        status == RuntimeStatus.running) {
      return;
    }

    final connectionEpoch = ++_runtimeConnectionEpoch;
    _runtimeReconnectTimer?.cancel();
    _runtimeReconnectTimer = null;
    _startingRuntime = true;
    _invalidateThreadRefreshes();
    _clearRuntimeResolvedConfiguration();
    _runtimeLogs.clear();
    status = RuntimeStatus.starting;
    lastError = null;
    _add(TimelineKind.system, '正在启动本地运行时', 'codex app-server · $workspace');
    notifyListeners();

    try {
      await Future.wait([_runtimeLoad, _workspaceLoad, _historyLoad]);
      if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
      final probe = await _inspectRuntime(notify: false);
      if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
      if (!probe.isAvailable) {
        throw StateError(probe.error ?? 'Codex CLI 不可用。');
      }
      _eventSubscription ??= _server.events.listen(_handleServerEvent);
      if (_server.isRunning) await _server.stop();
      if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
      await _server.start(workingDirectory: workspace);
      if (!_isCurrentRuntimeConnection(connectionEpoch)) {
        // 启动进程期间可能已切换连接代次；此时必须回收刚创建的旧进程。
        // The connection epoch may change while spawning; reclaim that now-stale process immediately.
        await _server.stop();
        return;
      }
      await _server.initialize();
      if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
      await refreshCodexConfiguration(notify: false);
      if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
      await refreshAccount();
      if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
      await _refreshReasoningEffortCapabilities();
      if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
      status = RuntimeStatus.ready;
      _runtimeReconnectAttempt = 0;
      if (pluginRuntimeRestartRequired) {
        pluginRuntimeRestartRequired = false;
        pluginActionResult = '运行时已重启，最新插件配置将在新建任务中生效。';
      }
      _add(TimelineKind.system, '运行时已连接', 'App Server 已通过本地 stdio 通道就绪。');
      await refreshThreads();
      await _resumeRestoredThreadIfNeeded();
      await refreshSkills(notify: false);
    } catch (error) {
      if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
      status = RuntimeStatus.failed;
      lastError = _messageOf(error);
      _add(TimelineKind.error, '无法启动运行时', lastError!);
    } finally {
      _startingRuntime = false;
    }
    if (!_isCurrentRuntimeConnection(connectionEpoch)) return;
    if (status == RuntimeStatus.failed) _scheduleRuntimeReconnect();
    notifyListeners();
  }

  /// 等待本地配置、工作区和历史恢复完成，并为已恢复的主目录自动连接运行时。
  /// Waits for local configuration, workspace, and history restoration, then automatically connects the restored primary directory.
  Future<void> connectRestoredWorkspace() async {
    await Future.wait([_runtimeLoad, _workspaceLoad, _historyLoad]);
    if (_disposed || workspacePath == null || status != RuntimeStatus.stopped) {
      return;
    }
    await startRuntime();
  }

  /// 向当前或新建线程发送用户提示词，并返回任务是否已成功启动。
  /// Sends a prompt to the current or a new thread and reports whether the turn started.
  Future<bool> sendPrompt(
    String prompt, {
    List<JsonMap> additionalInput = const [],
    String? goal,
    bool planMode = false,
    List<String> imagePaths = const [],
  }) async {
    final text = prompt.trim();
    if (text.isEmpty || !canSend) return false;
    if (activeThreadId != null && !_activeThreadAttached) {
      lastError = '当前历史任务尚未恢复，请先点击左侧任务后再发送。';
      _add(TimelineKind.error, '无法继续历史任务', lastError!);
      notifyListeners();
      return false;
    }
    final workspace = workspacePath!;
    if (activeThreadId == null) {
      _resetConversationTimeline();
      _clearFileChanges();
    }
    status = RuntimeStatus.running;
    lastError = null;
    _clearStreamingState();
    _activeTurnStartedAt = DateTime.now();
    _add(TimelineKind.user, '你', text, imagePaths: imagePaths);
    notifyListeners();

    try {
      activeThreadId ??= await _server.startThread(
        workingDirectory: workspace,
        runtimeWorkspaceRoots: workspaceRoots.length > 1
            ? workspaceRoots
            : null,
        modelProvider: null,
        model: _modelOverrideForNewThread,
        config: _newThreadConfig(),
      );
      _ownedThreadIds.add(activeThreadId!);
      _threadHistoryInitialized = true;
      _activeThreadAttached = true;
      // App Server may not include a newly-created thread in the first list
      // response while its turn is already running. Keep a lightweight local
      // row so the sidebar can still identify and show the active task.
      _ensureActiveThreadVisible(activeThreadId!, text);
      await refreshThreads();
      final id = activeThreadId!;
      _updateThreadStatus(id, 'active');
      final objective = goal?.trim();
      if (objective != null && objective.isNotEmpty) {
        await _server.setThreadGoal(threadId: id, objective: objective);
      }
      final shortId = id.length > 12 ? id.substring(0, 12) : id;
      _add(TimelineKind.system, '任务已创建', 'Thread $shortId');
      await _server.startTurn(
        threadId: id,
        prompt: text,
        workingDirectory: workspace,
        additionalInput: additionalInput,
        collaborationMode: _newThreadModelId == null
            ? null
            : {
                'mode': planMode ? 'plan' : 'default',
                'settings': {
                  'model': _newThreadModelId,
                  'reasoning_effort': reasoningEffort.configValue,
                  'developer_instructions': null,
                },
              },
      );
      notifyListeners();
      return true;
    } catch (error) {
      status = _server.isRunning ? RuntimeStatus.ready : RuntimeStatus.failed;
      _clearStreamingState();
      lastError = _messageOf(error);
      _updateThreadStatus(activeThreadId, 'systemError');
      _add(TimelineKind.error, '任务未能启动', lastError!);
    }
    if (status == RuntimeStatus.failed) _scheduleRuntimeReconnect();
    notifyListeners();
    return false;
  }

  /// Keeps the just-created active thread visible while the server list catches up.
  /// 在服务端线程列表同步前，先保留刚创建的活动任务行。
  void _ensureActiveThreadVisible(String threadId, String preview) {
    if (threads.any((thread) => thread.id == threadId)) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    threads = [
      ...threads,
      CodexThread(
        id: threadId,
        preview: preview,
        createdAt: now,
        updatedAt: now,
        status: 'active',
      ),
    ];
  }

  /// Refreshes the workspace-scoped skills advertised by App Server.
  Future<void> refreshSkills({
    bool forceReload = false,
    bool notify = true,
  }) async {
    final workspace = workspacePath;
    if (!_server.isRunning || workspace == null || skillsLoading) return;
    skillsLoading = true;
    skillsError = null;
    if (notify && !_disposed) notifyListeners();
    try {
      final rows = await _server.listSkills(
        workingDirectory: workspace,
        forceReload: forceReload,
      );
      if (_disposed || workspacePath != workspace) return;
      skills = rows
          .map(CodexSkill.fromJson)
          .whereType<CodexSkill>()
          .where((skill) => skill.enabled)
          .toList(growable: false);
    } catch (error) {
      if (_disposed || workspacePath != workspace) return;
      skillsError = _messageOf(error);
    } finally {
      if (!_disposed && workspacePath == workspace) {
        skillsLoading = false;
        if (notify) notifyListeners();
      }
    }
  }

  /// 请求 App Server 中断当前正在执行的任务。
  /// Requests that App Server interrupt the currently executing task.
  Future<void> stopCurrentTurn() async {
    final threadId = activeThreadId;
    if (threadId == null || status != RuntimeStatus.running) return;
    try {
      await _server.interruptTurn(threadId: threadId);
      _add(TimelineKind.system, '已请求停止', '正在等待 App Server 结束当前任务。');
    } catch (error) {
      _add(TimelineKind.error, '停止失败', _messageOf(error));
    }
    notifyListeners();
  }

  /// Sends a correction to the active turn through `turn/steer`.
  /// 调整方向不会创建新 turn，而是继续当前线程中的活动 turn。
  Future<bool> steerCurrentTurn(
    String prompt, {
    List<JsonMap> additionalInput = const [],
    List<String> imagePaths = const [],
  }) async {
    final text = prompt.trim();
    final threadId = activeThreadId;
    final turnId = activeTurnId;
    if (text.isEmpty || !canSteer || threadId == null || turnId == null) {
      return false;
    }
    _add(TimelineKind.user, '你', text, imagePaths: imagePaths);
    lastError = null;
    notifyListeners();
    try {
      final nextTurnId = await _server.steerTurn(
        threadId: threadId,
        expectedTurnId: turnId,
        prompt: text,
        additionalInput: additionalInput,
      );
      if (status == RuntimeStatus.running && activeThreadId == threadId) {
        activeTurnId = nextTurnId;
      }
      notifyListeners();
      return true;
    } catch (error) {
      lastError = _messageOf(error);
      _add(TimelineKind.error, '调整方向失败', lastError!);
      notifyListeners();
      return false;
    }
  }

  /// 停止 App Server 并重置仅在运行期有效的状态。
  /// Stops App Server and resets state that is only valid while it runs.
  Future<void> stopRuntime() async {
    if (status == RuntimeStatus.stopped && !_server.isRunning) return;
    _runtimeConnectionEpoch++;
    _runtimeReconnectTimer?.cancel();
    _runtimeReconnectTimer = null;
    try {
      await _server.stop();
      _invalidateThreadRefreshes();
      _clearRuntimeResolvedConfiguration();
      status = RuntimeStatus.stopped;
      activeThreadId = null;
      _activeThreadAttached = false;
      pendingApproval = null;
      approvalResponding = false;
      _clearStreamingState();
      _add(TimelineKind.system, '运行时连接已关闭', '应用会在需要时自动重新连接。');
    } catch (error) {
      status = RuntimeStatus.failed;
      lastError = _messageOf(error);
      _add(TimelineKind.error, '停止运行时失败', lastError!);
    }
    notifyListeners();
  }

  /// 在没有任务执行时自动重建当前主目录的运行时连接。
  /// Automatically rebuilds the current primary directory's runtime connection while no task is executing.
  Future<void> reconnectRuntime() async {
    if (workspacePath == null ||
        status == RuntimeStatus.running ||
        status == RuntimeStatus.starting ||
        _startingRuntime) {
      return;
    }
    if (_server.isRunning || status == RuntimeStatus.ready) {
      await stopRuntime();
      if (_server.isRunning) return;
    }
    await startRuntime();
  }

  /// 判断异步连接步骤是否仍属于当前控制器和最新连接代次。
  /// Determines whether an asynchronous connection step still belongs to this controller and connection epoch.
  bool _isCurrentRuntimeConnection(int epoch) =>
      !_disposed && epoch == _runtimeConnectionEpoch;

  /// 使用有限退避自动恢复失败或意外退出的运行时，避免无限重启循环。
  /// Automatically restores a failed or exited runtime with bounded backoff to avoid an infinite restart loop.
  void _scheduleRuntimeReconnect() {
    if (_disposed ||
        workspacePath == null ||
        status != RuntimeStatus.failed ||
        _runtimeReconnectTimer != null ||
        _runtimeReconnectAttempt >= _runtimeReconnectDelays.length) {
      return;
    }
    final delay = _runtimeReconnectDelays[_runtimeReconnectAttempt++];
    _add(TimelineKind.system, '等待自动重连', '${delay.inSeconds} 秒后重新连接本地运行时。');
    _runtimeReconnectTimer = Timer(delay, () {
      _runtimeReconnectTimer = null;
      if (_disposed || status != RuntimeStatus.failed) return;
      unawaited(reconnectRuntime());
    });
  }

  /// 从 App Server 分页刷新当前工作区的活跃线程列表。
  /// Refreshes the current workspace's active thread list from App Server pages.
  ///
  /// 当删除通知或删除请求刚完成时，服务端空列表是权威结果，不应由旧本地
  /// session 元数据重新填充。
  /// When a deletion event or request has just completed, an empty server list is
  /// authoritative and must not be repopulated from stale local session metadata.
  Future<void> refreshThreads({bool allowLocalSessionFallback = true}) async {
    final workspace = workspacePath;
    if (!_server.isRunning || workspace == null) return;
    final epoch = _threadRefreshEpoch;
    final request = ++_threadRefreshRequest;
    threadsLoading = true;
    threadsError = null;
    if (!_disposed) notifyListeners();
    try {
      final serverThreads =
          (await _server.listThreads(workingDirectory: workspace))
              .map(CodexThread.fromJson)
              .map((thread) {
                final localStatus = _localThreadStatuses[thread.id];
                return localStatus == null
                    ? thread
                    : thread.copyWith(status: localStatus);
              })
              .toList(growable: false);
      var nextThreads = _threadHistoryInitialized
          ? serverThreads
                .where((thread) => _ownedThreadIds.contains(thread.id))
                .toList(growable: false)
          : serverThreads;
      if (serverThreads.isEmpty && allowLocalSessionFallback) {
        final localThreads = await _localSessionThreadStore.listThreads(
          workspace,
        );
        nextThreads = localThreads
            .where(
              (thread) =>
                  !_threadHistoryInitialized ||
                  _ownedThreadIds.contains(thread.id),
            )
            .map((thread) {
              final localStatus = _localThreadStatuses[thread.id];
              return localStatus == null
                  ? thread
                  : thread.copyWith(status: localStatus);
            })
            .toList(growable: false);
        final activeId = activeThreadId;
        if (activeId != null &&
            !nextThreads.any((thread) => thread.id == activeId)) {
          final cachedActive = _cachedThread(activeId);
          if (cachedActive != null) {
            nextThreads = [...nextThreads, cachedActive];
          }
        }
      }
      // A non-empty server response can still briefly omit the newly-created
      // active thread. Preserve its local placeholder until the next refresh.
      final activeId = activeThreadId;
      if (activeId != null &&
          !nextThreads.any((thread) => thread.id == activeId)) {
        final cachedActive = _cachedThread(activeId);
        if (cachedActive != null) nextThreads = [...nextThreads, cachedActive];
      }
      if (_isCurrentThreadRefresh(request, epoch, workspace)) {
        threads = nextThreads;
        _scheduleConversationHistorySave();
      }
    } catch (error) {
      if (_isCurrentThreadRefresh(request, epoch, workspace)) {
        threadsError = _messageOf(error);
      }
    } finally {
      if (_isCurrentThreadRefresh(request, epoch, workspace)) {
        threadsLoading = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  /// 切换指定任务在当前项目列表中的置顶状态，并保存到本地历史缓存。
  /// Toggles a task's pinned state in the current workspace list and persists it in local history.
  void toggleThreadPinned(CodexThread thread) {
    if (!threads.any((value) => value.id == thread.id)) return;
    if (!_pinnedThreadIds.add(thread.id)) _pinnedThreadIds.remove(thread.id);
    _scheduleConversationHistorySave();
    if (!_disposed) notifyListeners();
  }

  /// 导出当前项目的本地缓存为可移植 JSON；不会导出密钥，也不会导出 App Server 原始 session。
  /// Exports the current workspace cache as portable JSON without keys or original App Server sessions.
  String exportConversationHistory() {
    final workspace = workspacePath;
    if (workspace == null) {
      throw StateError('请先选择一个本地项目，再导出历史记录。');
    }
    return jsonEncode(
      PortableConversationHistory(
        workspace: workspace,
        exportedAt: DateTime.now(),
        snapshot: _conversationHistorySnapshot(),
      ).toJson(),
    );
  }

  /// 将可移植 JSON 导入到当前项目的本地缓存；导入不会恢复远端或 App Server 的原始 session。
  /// Imports portable JSON into the current workspace cache without restoring remote or App Server sessions.
  Future<void> importConversationHistory(String encoded) async {
    final workspace = workspacePath;
    if (workspace == null) {
      throw StateError('请先选择一个本地项目，再导入历史记录。');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('历史导出文件的根节点必须是 JSON 对象。');
    }
    final imported = PortableConversationHistory.fromJson(decoded);
    final snapshot = imported.snapshot;
    _invalidateThreadRefreshes();
    _threadViewCache.clear();
    activeThreadId = null;
    _activeThreadAttached = false;
    threads = List.of(snapshot.threads);
    archivedThreads = List.of(snapshot.archivedThreads);
    _pinnedThreadIds
      ..clear()
      ..addAll(snapshot.pinnedThreadIds);
    _clearStreamingState();
    _entries
      ..clear()
      ..addAll(snapshot.entries);
    _fileChangesByPath
      ..clear()
      ..addEntries(
        snapshot.fileChanges.map((change) => MapEntry(change.path, change)),
      );
    turnDiff = snapshot.turnDiff;
    // Imported history may contain file metadata without file-level Diff.
    // Hydrate safe untracked-file previews after restoring the snapshot.
    unawaited(_hydrateMissingFileChangeDiffs());
    _add(
      TimelineKind.system,
      '已导入本地历史',
      '导出来源：${imported.workspace.isEmpty ? '未知项目' : imported.workspace}。仅恢复本应用缓存，不恢复 App Server 原始任务。',
    );
    await _saveConversationHistory();
    if (!_disposed) notifyListeners();
  }

  /// 从本机 Codex CLI 刷新已安装和可安装插件。
  /// Refreshes installed and available plugins from the local Codex CLI.
  Future<void> refreshPlugins() async {
    if (pluginSaving) return;
    pluginsLoading = true;
    pluginsError = null;
    if (!_disposed) notifyListeners();
    try {
      plugins = await _pluginStore.listPlugins();
    } catch (error) {
      pluginsError = _messageOf(error);
    } finally {
      pluginsLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 从本机 Codex CLI 刷新 marketplace 来源列表。
  /// Refreshes marketplace sources from the local Codex CLI.
  Future<void> refreshMarketplaces() async {
    if (pluginSaving) return;
    marketplacesLoading = true;
    marketplacesError = null;
    if (!_disposed) notifyListeners();
    try {
      marketplaces = await _pluginStore.listMarketplaces();
    } catch (error) {
      marketplacesError = _messageOf(error);
    } finally {
      marketplacesLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 注册一个本地 marketplace，并刷新可安装插件。
  /// Registers a local marketplace and refreshes installable plugins.
  Future<void> addLocalPluginMarketplace(String directory) async {
    await _runPluginAction(
      () => _pluginStore.addLocalMarketplace(directory),
      '已添加本地插件市场',
      progressMessage: '正在添加本地插件市场…',
    );
  }

  /// 注册本地或远程 marketplace，并刷新插件和来源列表。
  /// Registers a local or remote marketplace and refreshes plugins and sources.
  Future<void> addPluginMarketplace(String source) async {
    await _runPluginAction(
      () => _pluginStore.addMarketplace(source),
      '已添加插件市场',
      progressMessage: '正在添加插件市场…',
    );
  }

  /// 刷新一个 Git marketplace；名称为空时刷新所有 Git marketplace。
  /// Refreshes one Git marketplace, or all Git marketplaces when name is null.
  Future<void> upgradePluginMarketplace(String? name) async {
    await _runPluginAction(
      () => _pluginStore.upgradeMarketplace(name),
      name == null ? '已刷新所有 Git 插件市场' : '已刷新插件市场：$name',
      progressMessage: name == null ? '正在刷新所有 Git 插件市场…' : '正在刷新插件市场 $name…',
      targetId: name,
    );
  }

  /// 移除一个 marketplace，并重新读取插件与来源。
  /// Removes a marketplace and reloads plugins and sources.
  Future<void> removePluginMarketplace(CodexMarketplace marketplace) async {
    await _runPluginAction(
      () => _pluginStore.removeMarketplace(marketplace),
      '已移除插件市场：${marketplace.name}',
      progressMessage: '正在移除插件市场 ${marketplace.name}…',
      targetId: marketplace.name,
    );
  }

  /// 安装所选 marketplace 插件，并刷新插件列表。
  /// Installs the selected marketplace plugin and refreshes the plugin list.
  Future<void> installPlugin(CodexPlugin plugin) async {
    await _runPluginAction(
      () => _pluginStore.installPlugin(plugin),
      '已安装插件：${plugin.name}',
      progressMessage: '正在安装插件 ${plugin.name}…',
      targetId: plugin.id,
    );
  }

  /// 卸载已安装插件，并刷新当前插件列表。
  /// Uninstalls an installed plugin and refreshes the current plugin list.
  Future<void> removePlugin(CodexPlugin plugin) async {
    await _runPluginAction(
      () => _pluginStore.removePlugin(plugin),
      '已卸载插件：${plugin.name}',
      progressMessage: '正在卸载插件 ${plugin.name}…',
      targetId: plugin.id,
    );
  }

  /// 更新插件启用状态；新状态会在下一个运行时会话生效。
  /// Updates a plugin enabled state; it takes effect in the next runtime session.
  Future<void> setPluginEnabled(CodexPlugin plugin, bool enabled) async {
    await _runPluginAction(
      () => _pluginStore.setPluginEnabled(plugin, enabled),
      '${enabled ? '已启用' : '已停用'}插件：${plugin.name}',
      progressMessage: '正在${enabled ? '启用' : '停用'}插件 ${plugin.name}…',
      targetId: plugin.id,
    );
  }

  /// 从 App Server 分页刷新当前工作区的归档线程列表。
  /// Refreshes the current workspace's archived thread list from App Server pages.
  Future<void> refreshArchivedThreads() async {
    final workspace = workspacePath;
    if (!_server.isRunning || workspace == null) return;
    final epoch = _threadRefreshEpoch;
    final request = ++_archivedThreadRefreshRequest;
    archivedThreadsLoading = true;
    archivedThreadsError = null;
    if (!_disposed) notifyListeners();
    try {
      final nextThreads =
          (await _server.listThreads(
                workingDirectory: workspace,
                archived: true,
              ))
              .map(CodexThread.fromJson)
              .where(
                (thread) =>
                    !_threadHistoryInitialized ||
                    _ownedThreadIds.contains(thread.id),
              )
              .toList(growable: false);
      if (_isCurrentArchivedThreadRefresh(request, epoch, workspace)) {
        archivedThreads = nextThreads;
        _scheduleConversationHistorySave();
      }
    } catch (error) {
      if (_isCurrentArchivedThreadRefresh(request, epoch, workspace)) {
        archivedThreadsError = _messageOf(error);
      }
    } finally {
      if (_isCurrentArchivedThreadRefresh(request, epoch, workspace)) {
        archivedThreadsLoading = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  /// 恢复指定线程，并将其历史消息与工具记录写入时间线。
  /// Resumes a thread and writes its historic messages and tool records to the timeline.
  Future<void> resumeThread(CodexThread thread) async {
    if (status != RuntimeStatus.ready || !_server.isRunning) return;
    if (activeThreadId == thread.id && _activeThreadAttached) return;
    _cacheActiveThreadView();
    final cachedView = _cachedThreadView(thread.id);
    _resumingThread = true;
    final previousThreadId = activeThreadId;
    final previousThreadAttached = _activeThreadAttached;
    final previousView = previousThreadId == null
        ? null
        : _currentThreadViewSnapshot();
    var viewLoaded = cachedView != null;
    activeThreadId = thread.id;
    _activeThreadAttached = false;
    status = RuntimeStatus.starting;
    lastError = null;
    _clearStreamingState();
    if (cachedView != null) {
      _restoreThreadView(cachedView);
    } else {
      _clearThreadTimelineForRestoration();
    }
    notifyListeners();
    try {
      final resumeResult = await _server.resumeThread(
        threadId: thread.id,
        modelProvider: thread.modelProvider,
        model: thread.model,
        config: null,
      );
      activeThreadId = thread.id;
      _activeThreadAttached = true;
      status = RuntimeStatus.ready;
      try {
        if (cachedView == null) {
          final history = await _loadThreadHistory(
            threadId: thread.id,
            resumeResult: resumeResult,
          );
          _resetConversationTimeline();
          _appendThreadHistory(history);
          viewLoaded = true;
          final incompleteItemTurnCount =
              history['incompleteItemTurnCount'] as int? ?? 0;
          final incompleteTurnHistory =
              history['incompleteTurnHistory'] == true;
          if (incompleteTurnHistory || incompleteItemTurnCount > 0) {
            final detail = [
              if (incompleteTurnHistory) '部分历史 turns',
              if (incompleteItemTurnCount > 0)
                '$incompleteItemTurnCount 个 turn 的 items',
            ].join('和');
            _add(TimelineKind.system, '历史内容未完全加载', '$detail 超出安全页数限制。');
          }
        }
      } catch (error) {
        // Resuming the remote thread succeeded. A history page may still be
        // unavailable, but that must not turn the next message into a new
        // thread.
        _add(TimelineKind.error, '历史内容加载不完整', _messageOf(error));
      }
      if (cachedView == null) {
        _add(TimelineKind.system, '任务已恢复', '可以继续在此任务中追问。');
      }
      if (viewLoaded) _cacheActiveThreadView();
      await refreshThreads();
    } catch (error) {
      activeThreadId = previousThreadId;
      _activeThreadAttached = previousThreadAttached;
      status = RuntimeStatus.ready;
      if (previousView != null) _restoreThreadView(previousView);
      lastError = _messageOf(error);
      _add(TimelineKind.error, '无法恢复任务', lastError!);
    }
    _resumingThread = false;
    notifyListeners();
  }

  /// 自动恢复本地快照中上次打开的线程，避免重启后发送消息创建新线程。
  /// Reattaches the thread that was open in the restored snapshot before the
  /// first follow-up message is sent after an app restart.
  Future<void> _resumeRestoredThreadIfNeeded() async {
    final id = activeThreadId;
    if (id == null || _activeThreadAttached || status != RuntimeStatus.ready) {
      return;
    }
    CodexThread? thread;
    for (final candidate in [...threads, ...archivedThreads]) {
      if (candidate.id == id) {
        thread = candidate;
        break;
      }
    }
    if (thread == null) return;
    await resumeThread(thread);
  }

  /// 返回当前活动线程的本地缓存候选，供服务端暂时返回空列表时恢复。
  /// Returns a cached active or archived thread that can be used for recovery.
  CodexThread? _cachedThread(String id) {
    for (final thread in [...threads, ...archivedThreads]) {
      if (thread.id == id) return thread;
    }
    return null;
  }

  /// 在服务器上更新线程名称，并同步本地列表。
  /// Updates a thread name on the server and synchronizes local lists.
  Future<void> renameThread(CodexThread thread, String name) async {
    final title = name.trim();
    if (title.isEmpty || !_server.isRunning) return;
    try {
      await _server.renameThread(threadId: thread.id, name: title);
      threads = threads
          .map(
            (value) =>
                value.id == thread.id ? value.copyWith(name: title) : value,
          )
          .toList(growable: false);
      _add(TimelineKind.system, '任务已重命名', title);
    } catch (error) {
      lastError = _messageOf(error);
      _add(TimelineKind.error, '重命名失败', lastError!);
    }
    notifyListeners();
  }

  /// 归档指定线程并刷新活跃线程状态。
  /// Archives a thread and refreshes active thread state.
  Future<void> archiveThread(CodexThread thread) async {
    await archiveThreads([thread]);
  }

  /// 批量归档指定线程，并在成功后更新当前项目的本地列表。
  /// Archives selected threads in sequence and updates the current workspace list after each success.
  Future<Set<String>> archiveThreads(Iterable<CodexThread> selected) async {
    final items =
        <String, CodexThread>{for (final thread in selected) thread.id: thread}
            .values
            .where((thread) => !_archivingThreadIds.contains(thread.id))
            .toList(growable: false);
    if (!_server.isRunning ||
        status == RuntimeStatus.running ||
        items.isEmpty) {
      return const <String>{};
    }
    _archivingThreadIds.addAll(items.map((thread) => thread.id));
    if (!_disposed) notifyListeners();
    final archivedIds = <String>{};
    Object? failure;
    try {
      for (final thread in items) {
        try {
          await _server.archiveThread(threadId: thread.id);
        } catch (error) {
          failure = error;
          break;
        }
        archivedIds.add(thread.id);
        _localThreadStatuses.remove(thread.id);
        _threadViewCache.remove(thread.id);
        threads = threads
            .where((value) => value.id != thread.id)
            .toList(growable: false);
        _pinnedThreadIds.remove(thread.id);
        if (activeThreadId == thread.id) {
          activeThreadId = null;
          _activeThreadAttached = false;
          _resetConversationTimeline();
          _clearStreamingState();
        }
      }
      if (archivedIds.isNotEmpty) {
        _scheduleConversationHistorySave();
        _add(
          TimelineKind.system,
          archivedIds.length == 1 ? '任务已归档' : '任务已批量归档',
          archivedIds.length == 1
              ? items
                    .firstWhere((thread) => thread.id == archivedIds.single)
                    .title
              : '已归档 ${archivedIds.length} 个任务。',
        );
      }
      if (failure != null) {
        lastError = _messageOf(failure);
        _add(
          TimelineKind.error,
          archivedIds.isEmpty ? '归档失败' : '部分任务归档失败',
          lastError!,
        );
      }
    } finally {
      _archivingThreadIds.removeAll(items.map((thread) => thread.id));
      if (!_disposed) notifyListeners();
    }
    return archivedIds;
  }

  /// 永久删除指定任务及 App Server 定义的派生任务，并清理本应用的对应缓存引用。
  /// Permanently deletes a task and App Server-defined descendants, then removes matching local cache references.
  Future<void> deleteThread(CodexThread thread) async {
    if (!_server.isRunning ||
        status == RuntimeStatus.running ||
        !_deletingThreadIds.add(thread.id)) {
      return;
    }
    if (!_disposed) notifyListeners();
    try {
      await _server.deleteThread(threadId: thread.id);
      threads = threads
          .where((value) => value.id != thread.id)
          .toList(growable: false);
      archivedThreads = archivedThreads
          .where((value) => value.id != thread.id)
          .toList(growable: false);
      _localThreadStatuses.remove(thread.id);
      _threadViewCache.remove(thread.id);
      _pinnedThreadIds.remove(thread.id);
      if (activeThreadId == thread.id) {
        activeThreadId = null;
        _activeThreadAttached = false;
        _resetConversationTimeline();
        _clearStreamingState();
      }
      _scheduleConversationHistorySave();
      _add(TimelineKind.system, '任务已永久删除', thread.title);
      await Future.wait([
        refreshThreads(allowLocalSessionFallback: false),
        refreshArchivedThreads(),
      ]);
    } catch (error) {
      lastError = _messageOf(error);
      _add(TimelineKind.error, '删除任务失败', lastError!);
    } finally {
      _deletingThreadIds.remove(thread.id);
      if (!_disposed) notifyListeners();
    }
  }

  /// 判断指定任务是否正处于归档或删除处理中。
  /// Determines whether a task is currently being archived or deleted.
  bool isUpdatingThread(String threadId) =>
      _archivingThreadIds.contains(threadId) ||
      _deletingThreadIds.contains(threadId);

  /// 恢复归档线程，并防止对同一线程重复提交恢复请求。
  /// Unarchives a thread while preventing duplicate requests for that thread.
  Future<void> unarchiveThread(CodexThread thread) async {
    if (!_server.isRunning ||
        status != RuntimeStatus.ready ||
        !_unarchivingThreadIds.add(thread.id)) {
      return;
    }
    notifyListeners();
    try {
      await _server.unarchiveThread(threadId: thread.id);
      archivedThreads = archivedThreads
          .where((value) => value.id != thread.id)
          .toList(growable: false);
      _add(TimelineKind.system, '任务已恢复到列表', thread.title);
      await Future.wait([refreshThreads(), refreshArchivedThreads()]);
    } catch (error) {
      lastError = _messageOf(error);
      _add(TimelineKind.error, '恢复归档任务失败', lastError!);
    } finally {
      _unarchivingThreadIds.remove(thread.id);
      if (!_disposed) notifyListeners();
    }
  }

  /// 选择并异步保存后续任务要使用的推理强度。
  /// Selects and asynchronously persists the reasoning effort for subsequent tasks.
  Future<void> setReasoningEffort(ReasoningEffort value) async {
    await _runtimeLoad;
    if (!reasoningEffortOptions.contains(value)) return;
    if (reasoningEffort == value) return;
    reasoningEffort = value;
    _add(
      TimelineKind.system,
      '推理强度已更新',
      value == ReasoningEffort.defaultValue
          ? '将使用模型默认推理强度。'
          : '将用于后续新建任务：${value.label}。',
    );
    notifyListeners();
    try {
      await _saveReasoningEffort(value);
    } catch (error) {
      _add(TimelineKind.error, '无法保存推理强度', _messageOf(error));
      if (!_disposed) notifyListeners();
    }
  }

  /// 选择后续新建任务的模型；传入 `null` 时恢复为跟随 Codex 配置。
  /// Selects the model for subsequent new tasks; passing `null` restores configuration-following behavior.
  Future<void> setModel(String? value) async {
    await _runtimeLoad;
    final normalized = _nonEmptyConfigString(value);
    if (normalized != null &&
        !modelOptions.any((option) => option.id == normalized)) {
      return;
    }
    if (selectedModelId == normalized) return;
    selectedModelId = normalized;
    final effortWasReset = _updateReasoningEffortOptions();
    _add(
      TimelineKind.system,
      '新任务模型已更新',
      normalized == null
          ? '后续新建任务将跟随 Codex 配置：$configuredModelLabel。'
          : '后续新建任务将使用：$newTaskModelLabel。',
    );
    notifyListeners();
    try {
      await _saveModelSelection(normalized);
      if (effortWasReset) {
        await _saveReasoningEffort(ReasoningEffort.defaultValue);
      }
    } catch (error) {
      _add(TimelineKind.error, '无法保存模型选择', _messageOf(error));
      if (!_disposed) notifyListeners();
    }
  }

  /// 探测当前 Codex CLI 路径及其可用性。
  /// Probes the current Codex CLI path and availability.
  Future<void> inspectRuntime() async {
    await _runtimeLoad;
    final probe = await _inspectRuntime(notify: true);
    if (probe.isAvailable &&
        status == RuntimeStatus.failed &&
        workspacePath != null &&
        !_disposed) {
      _runtimeReconnectAttempt = 0;
      await reconnectRuntime();
    }
  }

  /// 验证并保存用户指定的 Codex CLI 可执行文件路径。
  /// Validates and saves a user-specified Codex CLI executable path.
  Future<void> setRuntimeExecutable(String path) async {
    if (!canConfigureRuntime) {
      runtimeError = '请等待当前任务完成后再修改 Codex CLI 路径。';
      notifyListeners();
      return;
    }
    await _runtimeLoad;
    final reconnect = workspacePath != null;
    if (_server.isRunning || status == RuntimeStatus.ready) {
      await stopRuntime();
      if (_server.isRunning) return;
    }
    final previous = _server.executable;
    runtimeChecking = true;
    runtimeError = null;
    notifyListeners();
    try {
      _server.setExecutable(path);
      final probe = await _inspectRuntime(notify: false);
      if (!probe.isAvailable || probe.executablePath == null) {
        throw StateError(probe.error ?? '所选文件不是可用的 Codex CLI。');
      }
      await _runtimeConfigurationStore.saveExecutable(probe.executablePath!);
      runtimeProbe = probe;
    } catch (error) {
      _server.setExecutable(previous);
      runtimeError = _messageOf(error);
    } finally {
      runtimeChecking = false;
      if (!_disposed) notifyListeners();
      if (reconnect && !_disposed) await startRuntime();
    }
  }

  /// 清除自定义 CLI 路径，恢复自动发现。
  /// Clears the custom CLI path and restores automatic discovery.
  Future<void> resetRuntimeExecutable() async {
    if (!canConfigureRuntime) {
      runtimeError = '请等待当前任务完成后再修改 Codex CLI 路径。';
      notifyListeners();
      return;
    }
    final reconnect = workspacePath != null;
    if (_server.isRunning || status == RuntimeStatus.ready) {
      await stopRuntime();
      if (_server.isRunning) return;
    }
    runtimeChecking = true;
    runtimeError = null;
    notifyListeners();
    try {
      _server.setExecutable(null);
      await _runtimeConfigurationStore.clear();
      await _inspectRuntime(notify: false);
    } catch (error) {
      runtimeError = _messageOf(error);
    } finally {
      runtimeChecking = false;
      if (!_disposed) notifyListeners();
      if (reconnect && !_disposed) await startRuntime();
    }
  }

  /// 从 App Server 读取并同步账户认证状态。
  /// Reads and synchronizes account authentication state from App Server.
  Future<void> refreshAccount() async {
    if (!_server.isRunning) return;
    authStatus = AuthStatus.checking;
    try {
      final accountResult = await _server.readAccount();
      _updateAccount(accountResult);
    } catch (error) {
      authStatus = AuthStatus.signedOut;
      lastError = _messageOf(error);
    }
    if (!_disposed) notifyListeners();
  }

  /// 请求 ChatGPT 浏览器登录地址，并更新登录进行状态。
  /// Requests a ChatGPT browser-login URL and updates login progress.
  Future<void> startChatgptLogin() async {
    if (!_server.isRunning || loginInProgress) return;
    loginInProgress = true;
    loginUrl = null;
    lastError = null;
    notifyListeners();
    try {
      final result = await _server.startChatgptLogin();
      final url = result['authUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw const FormatException('App Server did not return an auth URL.');
      }
      loginUrl = url;
      _add(TimelineKind.system, '等待 ChatGPT 登录', '请在浏览器中完成登录。');
    } catch (error) {
      loginInProgress = false;
      lastError = _messageOf(error);
      _add(TimelineKind.error, '无法开始登录', lastError!);
    }
    notifyListeners();
  }

  /// 将 API Key 仅提交给本地运行时并刷新账户状态。
  /// Submits an API key only to the local runtime and refreshes account state.
  Future<void> loginWithApiKey(String apiKey) async {
    final value = apiKey.trim();
    if (!_server.isRunning || value.isEmpty || loginInProgress) return;
    loginInProgress = true;
    loginUrl = null;
    lastError = null;
    notifyListeners();
    try {
      await _server.loginWithApiKey(value);
      await refreshAccount();
      _add(TimelineKind.system, 'API Key 已提交', '密钥仅交给本地 Codex 运行时处理。');
    } catch (error) {
      lastError = _messageOf(error);
      _add(TimelineKind.error, 'API Key 登录失败', lastError!);
    } finally {
      loginInProgress = false;
      notifyListeners();
    }
  }

  /// 对当前服务器审批请求作出允许或拒绝的答复。
  /// Answers the current server approval request by allowing or declining it.
  Future<void> respondToApproval({required bool accepted}) async {
    final approval = pendingApproval;
    if (approval == null || approvalResponding) return;

    approvalResponding = true;
    notifyListeners();
    try {
      _server.respond(approval.requestId, _approvalResult(approval, accepted));
      _add(TimelineKind.system, accepted ? '已允许本次操作' : '已拒绝操作', approval.title);
      pendingApproval = null;
    } catch (error) {
      lastError = _messageOf(error);
      _add(TimelineKind.error, '审批响应失败', lastError!);
    } finally {
      approvalResponding = false;
      notifyListeners();
    }
  }

  /// 更新并持久化审批策略；自动模式会立即处理之后收到的审批请求。
  /// Updates and persists the approval policy; auto mode immediately handles later approval requests.
  Future<void> setApprovalMode(ApprovalMode mode) async {
    _approvalModeChangedBeforeLoad = true;
    if (approvalMode == mode) {
      try {
        await _saveApprovalMode(mode);
      } catch (error) {
        lastError = _messageOf(error);
        _add(TimelineKind.error, '无法保存审批模式', lastError!);
        if (!_disposed) notifyListeners();
      }
      return;
    }
    approvalMode = mode;
    _add(
      TimelineKind.system,
      '审批模式已更新',
      mode == ApprovalMode.autoApprove
          ? '后续命令、文件变更和额外权限请求将由“帮我批准”自动处理。'
          : '后续请求会显示批准和拒绝按钮。',
    );
    if (mode == ApprovalMode.autoApprove && pendingApproval != null) {
      unawaited(respondToApproval(accepted: true));
    }
    notifyListeners();
    try {
      await _saveApprovalMode(mode);
    } catch (error) {
      lastError = _messageOf(error);
      _add(TimelineKind.error, '无法保存审批模式', lastError!);
      if (!_disposed) notifyListeners();
    }
  }

  /// 路由 App Server 事件，并更新时间线、审批和运行时状态。
  /// Routes an App Server event and updates timeline, approval, and runtime state.
  void _handleServerEvent(ServerEvent event) {
    if (_disposed) return;
    if (event.isServerRequest) {
      final approval = PendingApproval.fromEvent(event);
      if (approval == null) {
        _server.respondError(event.requestId!, '此客户端暂不支持 ${event.method}。');
        _add(TimelineKind.error, '未支持的运行时请求', event.method);
      } else {
        if (approvalMode == ApprovalMode.autoApprove) {
          try {
            _server.respond(
              approval.requestId,
              _approvalResult(approval, true),
            );
            _add(TimelineKind.system, '已自动批准本次操作', approval.title);
          } catch (error) {
            lastError = _messageOf(error);
            _add(TimelineKind.error, '自动审批响应失败', lastError!);
          }
        } else {
          pendingApproval = approval;
          approvalResponding = false;
          _add(TimelineKind.approval, approval.title, approval.detail);
        }
      }
      notifyListeners();
      return;
    }

    switch (event.method) {
      case 'account/updated':
        _updateAccount(event.params);
      case 'account/login/completed':
        loginInProgress = false;
        if (event.params['success'] == true) {
          loginUrl = null;
          unawaited(refreshAccount());
        } else {
          lastError = event.params['error']?.toString() ?? '登录未完成。';
        }
      case 'item/agentMessage/delta':
        _appendAgentDelta(event.params);
        _scheduleDeltaNotification();
        return;
      case 'turn/started':
        final turn = event.params['turn'];
        if (_isEventForActiveThread(event.params) && turn is Map) {
          activeTurnId = turn['id']?.toString();
          _activeTurnStartedAt =
              _turnStartedAt(JsonMap.from(turn)) ??
              _activeTurnStartedAt ??
              DateTime.now();
        }
      case 'item/started':
        _recordStartedCommand(event.params);
      case 'turn/plan/updated':
        if (_isEventForActiveTurn(event.params)) {
          _updateTaskPlan(event.params);
        }
      case 'item/completed':
        if (_isEventForActiveTurn(event.params)) {
          _recordCompletedCommand(event.params);
          _recordCompletedFileChange(event.params['item']);
        }
      case 'turn/diff/updated':
        if (_isEventForActiveTurn(event.params)) {
          _updateTurnDiff(event.params['diff']);
        }
      case 'turn/completed':
        if (_isEventForActiveTurn(event.params)) {
          _handleTurnCompleted(event.params);
        }
        unawaited(refreshThreads());
      case 'thread/archived':
      case 'thread/unarchived':
      case 'thread/name/updated':
        unawaited(refreshThreads());
        unawaited(refreshArchivedThreads());
      case 'thread/deleted':
        unawaited(refreshThreads(allowLocalSessionFallback: false));
        unawaited(refreshArchivedThreads());
      case 'runtime/stderr':
      case 'runtime/invalidMessage':
        _recordRuntimeLog(event.params['message']?.toString() ?? '');
      case 'runtime/exited':
        // 只有进程退出才会使连接失败；单个 turn 失败仍可继续复用当前连接。
        // Only process exit fails the connection; an individual failed turn remains recoverable in-place.
        status = RuntimeStatus.failed;
        // The next runtime process must attach the retained thread again.
        _activeThreadAttached = false;
        lastError = 'Codex runtime 已退出（code ${event.params['code']}）。';
        _updateThreadStatus(activeThreadId, 'systemError');
        pendingApproval = null;
        approvalResponding = false;
        _clearStreamingState();
        _recordRuntimeLog(lastError!, level: RuntimeLogLevel.error);
        _add(TimelineKind.error, '运行时已断开', lastError!);
        _scheduleRuntimeReconnect();
      case 'serverRequest/resolved':
        if (event.params['requestId'] == pendingApproval?.requestId) {
          pendingApproval = null;
          approvalResponding = false;
        }
      case 'skills/changed':
        unawaited(refreshSkills(forceReload: true));
      // Unrecognized notifications are protocol implementation details. In
      // particular, command output deltas can arrive very frequently and must
      // not become visible timeline entries.
      default:
        break;
    }
    notifyListeners();
  }

  @visibleForTesting
  /// 将服务器事件注入控制器，供测试验证事件处理。
  /// Injects a server event into the controller for event-handling tests.
  void handleServerEventForTesting(ServerEvent event) =>
      _handleServerEvent(event);

  @visibleForTesting
  /// 供展示层测试直接替换时间线内容，无需模拟完整的 App Server 历史恢复会话。
  /// Replaces timeline content for presentation tests without emulating a full App Server history-resume session.
  void replaceTimelineEntriesForTesting(Iterable<TimelineEntry> values) {
    _entries
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  /// 构造符合不同审批协议的允许或拒绝 JSON-RPC 结果。
  /// Builds an allow-or-deny JSON-RPC result for the relevant approval protocol.
  JsonMap _approvalResult(PendingApproval approval, bool accepted) {
    return switch (approval.kind) {
      ApprovalKind.command ||
      ApprovalKind.fileChange => {'decision': accepted ? 'accept' : 'decline'},
      ApprovalKind.permissions => {
        'permissions': accepted && approval.params['permissions'] is Map
            ? JsonMap.from(approval.params['permissions'] as Map)
            : <String, dynamic>{},
        if (accepted) 'scope': 'turn',
      },
    };
  }

  /// 从嵌套协议值中提取第一个可展示的文本内容。
  /// Extracts the first displayable text content from a nested protocol value.
  String _findText(Object? value) {
    if (value is String) return value;
    if (value is Map) {
      for (final key in ['delta', 'text', 'message']) {
        final found = _findText(value[key]);
        if (found.isNotEmpty) return found;
      }
      for (final candidate in value.values) {
        final found = _findText(candidate);
        if (found.isNotEmpty) return found;
      }
    }
    if (value is Iterable) {
      for (final candidate in value) {
        final found = _findText(candidate);
        if (found.isNotEmpty) return found;
      }
    }
    return '';
  }

  /// 将流式 Agent 文本增量合并进对应的时间线条目。
  /// Merges a streaming agent text delta into its matching timeline entry.
  void _appendAgentDelta(JsonMap params) {
    final text = params['delta'] is String
        ? params['delta'] as String
        : _findText(params);
    if (text.isEmpty) return;

    final itemId = params['itemId']?.toString() ?? 'active-agent-message';
    final index = _agentEntryIndexByItem[itemId];
    if (index == null) {
      _agentEntryIndexByItem[itemId] = _entries.length;
      _add(TimelineKind.agent, 'Codex', text);
      return;
    }
    final previous = _entries[index];
    _entries[index] = previous.copyWith(detail: '${previous.detail}$text');
  }

  /// 应用当前 turn 的结构化计划更新，并忽略已知属于其他 turn 的迟到通知。
  /// Applies a structured plan update for the current turn and ignores known late notifications from another turn.
  void _updateTaskPlan(JsonMap params) {
    final turnId = params['turnId']?.toString() ?? '';
    if (activeTurnId != null && turnId.isNotEmpty && turnId != activeTurnId) {
      return;
    }
    activeTurnId ??= turnId.isEmpty ? null : turnId;
    activeTaskPlan = TaskPlan.fromNotification(params);
  }

  /// 处理任务结束事件，并采集其中的文件变更与统一 Diff。
  /// Handles a completed turn and captures its file changes and unified diff.
  void _handleTurnCompleted(JsonMap params) {
    final turn = params['turn'];
    final turnMap = turn is Map
        ? JsonMap.from(turn)
        : const <String, dynamic>{};
    final completionStatus =
        turnMap['status']?.toString() ??
        params['status']?.toString() ??
        'completed';
    _appendTurnElapsed(turnMap);
    pendingApproval = null;
    approvalResponding = false;
    switch (completionStatus) {
      case 'failed':
        // Turn 失败属于任务级错误，不代表 stdio 运行时已断开。
        // A failed turn is a task-level error and does not imply that the stdio runtime disconnected.
        status = RuntimeStatus.ready;
        lastError = _findText(turnMap['error']).isNotEmpty
            ? _findText(turnMap['error'])
            : 'Codex 未能完成当前任务。';
        _updateThreadStatus(activeThreadId, 'systemError');
        _add(TimelineKind.error, '任务失败', lastError!);
      case 'interrupted':
        status = RuntimeStatus.ready;
        _updateThreadStatus(activeThreadId, 'idle');
        _add(TimelineKind.system, '任务已停止', '可以继续在同一线程追问。');
      default:
        status = RuntimeStatus.ready;
        _updateThreadStatus(activeThreadId, 'idle');
        _add(TimelineKind.system, '任务完成', '你可以继续在同一线程追问。');
    }
    _clearStreamingState();
  }

  /// Updates a cached task status immediately after a turn changes outcome.
  /// 在 turn 结果变化后立即更新本地任务状态，避免侧栏等待历史刷新。
  void _updateThreadStatus(String? threadId, String status) {
    if (threadId == null) return;
    _localThreadStatuses[threadId] = status;
    final index = threads.indexWhere((thread) => thread.id == threadId);
    if (index < 0) return;
    final nextThreads = List<CodexThread>.of(threads);
    nextThreads[index] = nextThreads[index].copyWith(status: status);
    threads = nextThreads;
    _scheduleConversationHistorySave();
  }

  /// 将恢复的线程历史项目转换为时间线、工具和文件变更记录。
  /// Converts resumed thread history items into timeline, tool, and file-change records.
  void _appendThreadHistory(JsonMap result) {
    final turns = result['turns'];
    if (turns is! Iterable) return;
    for (final rawTurn in turns) {
      if (rawTurn is! Map || rawTurn['items'] is! Iterable) continue;
      for (final rawItem in rawTurn['items'] as Iterable) {
        if (rawItem is! Map) continue;
        final item = JsonMap.from(rawItem);
        switch (item['type']) {
          case 'userMessage':
            final text = _findText(item['content']);
            if (text.isNotEmpty) _add(TimelineKind.user, '你', text);
          case 'agentMessage':
            final text = item['text']?.toString() ?? _findText(item);
            if (text.isNotEmpty) _add(TimelineKind.agent, 'Codex', text);
          case 'commandExecution':
            _appendCompletedCommandItem(item);
          case 'plan':
            final text = item['text']?.toString() ?? '';
            if (text.isNotEmpty) _add(TimelineKind.system, '计划', text);
          case 'reasoning':
            final summary = _findText(item['summary']);
            if (summary.isNotEmpty) {
              _add(TimelineKind.system, '推理摘要', summary);
            }
          case 'fileChange':
            _recordFileChanges(item['changes']);
          case 'mcpToolCall' ||
              'dynamicToolCall' ||
              'webSearch' ||
              'imageView' ||
              'imageGeneration' ||
              'sleep' ||
              'enteredReviewMode' ||
              'exitedReviewMode':
            _appendToolHistoryItem(item);
        }
      }
      _appendTurnElapsed(JsonMap.from(rawTurn));
    }
  }

  /// Keeps a single concise command line visible only while App Server marks a
  /// command-execution item as active. Output deltas intentionally remain
  /// hidden so the conversation does not turn into a terminal transcript.
  void _recordStartedCommand(JsonMap params) {
    if (!_isEventForActiveTurn(params)) return;
    final rawItem = params['item'];
    if (rawItem is! Map) return;
    final item = JsonMap.from(rawItem);
    if (item['type']?.toString() != 'commandExecution') return;
    final command = _label(item['command']);
    if (command.isEmpty) return;
    _activeCommand = command;
    _activeCommandItemId = _label(item['id']);
  }

  /// Converts a completed command item into the existing activity history and
  /// removes its transient live-command presentation.
  void _recordCompletedCommand(JsonMap params) {
    if (!_isEventForActiveTurn(params)) return;
    final rawItem = params['item'];
    if (rawItem is! Map) return;
    final item = JsonMap.from(rawItem);
    if (item['type']?.toString() != 'commandExecution') return;
    final itemId = _label(item['id']);
    if (itemId.isEmpty || itemId == _activeCommandItemId) {
      _activeCommand = null;
      _activeCommandItemId = null;
    }
    _appendCompletedCommandItem(item);
  }

  bool _isEventForActiveTurn(JsonMap params) {
    if (!_isEventForActiveThread(params)) return false;
    final turn = params['turn'];
    final threadId = _label(params['threadId']);
    final turnId = _label(
      params['turnId'] ?? (turn is Map ? turn['id'] : null),
    );
    // Some compatible App Server notifications omit both IDs. They may be the
    // first plan update for the current turn, so let the plan handler attach
    // them. Explicitly identified notifications must still match the open
    // turn and thread.
    return turnId.isEmpty ||
        activeTurnId == turnId ||
        (activeTurnId == null && threadId.isEmpty);
  }

  /// Limits timeline mutations to notifications for the thread being shown.
  /// A connection can remain subscribed to previously resumed threads.
  bool _isEventForActiveThread(JsonMap params) {
    final threadId = _label(params['threadId']);
    // Older App Server notifications may omit the thread ID, so retain that
    // compatibility. An explicitly identified event, however, must belong to
    // the task being shown; a blank task cannot receive a prior task's event.
    return threadId.isEmpty || threadId == activeThreadId;
  }

  void _appendCompletedCommandItem(JsonMap item) {
    final itemId = _label(item['id']);
    if (itemId.isNotEmpty && !_completedCommandItemIds.add(itemId)) return;
    final command = _label(item['command']);
    final output = _label(item['aggregatedOutput']);
    final detail = [
      command,
      output,
    ].where((value) => value.isNotEmpty).join('\n');
    if (detail.isNotEmpty) _add(TimelineKind.command, '执行命令', detail);
  }

  void _appendTurnElapsed(JsonMap turn) {
    final duration = _turnDuration(turn);
    if (duration == null) return;
    _add(TimelineKind.elapsed, '已处理 ${_formatTurnDuration(duration)}', '');
  }

  Duration? _turnDuration(JsonMap turn) {
    final durationMs = turn['durationMs'];
    if (durationMs is num && durationMs >= 0) {
      return Duration(milliseconds: durationMs.round());
    }
    final startedAt = _turnStartedAt(turn);
    final completedAt = _turnCompletedAt(turn);
    if (startedAt != null && completedAt != null) {
      return completedAt.difference(startedAt);
    }
    if (_activeTurnStartedAt != null) {
      return DateTime.now().difference(_activeTurnStartedAt!);
    }
    return null;
  }

  DateTime? _turnStartedAt(JsonMap turn) =>
      _unixSecondsToDateTime(turn['startedAt']);

  DateTime? _turnCompletedAt(JsonMap turn) =>
      _unixSecondsToDateTime(turn['completedAt']);

  DateTime? _unixSecondsToDateTime(Object? value) {
    if (value is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.round() * 1000);
  }

  String _formatTurnDuration(Duration duration) {
    final seconds = duration.inSeconds;
    final hours = seconds ~/ Duration.secondsPerHour;
    final minutes =
        (seconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    final remainingSeconds = seconds % Duration.secondsPerMinute;
    final parts = <String>[];
    if (hours > 0) parts.add('$hours 小时');
    if (minutes > 0 || hours > 0) parts.add('$minutes 分钟');
    if (remainingSeconds > 0 || parts.isEmpty) parts.add('$remainingSeconds 秒');
    return parts.join(' ');
  }

  /// 将专用工具历史项转换为可读的时间线条目。
  /// Converts a specialized tool-history item into a readable timeline entry.
  void _appendToolHistoryItem(JsonMap item) {
    final type = item['type']?.toString();
    final (title, detail) = switch (type) {
      'mcpToolCall' => (
        'MCP 工具：${_label(item['server'])}/${_label(item['tool'])}',
        _toolStatus(item),
      ),
      'dynamicToolCall' => (
        '动态工具：${_label(item['namespace'])}/${_label(item['tool'])}',
        _toolStatus(item),
      ),
      'webSearch' => ('网页搜索', _searchDetail(item)),
      'imageView' => ('查看图片', _label(item['path'])),
      'imageGeneration' => (
        '生成图片',
        _label(item['savedPath'] ?? item['status']),
      ),
      'sleep' => ('等待', '${_label(item['durationMs'])} ms'),
      'enteredReviewMode' => ('进入审查模式', _label(item['review'])),
      'exitedReviewMode' => ('退出审查模式', _label(item['review'])),
      _ => ('工具事件', ''),
    };
    if (detail.isNotEmpty) _add(TimelineKind.tool, title, detail);
  }

  /// 组合工具项状态及可用的耗时信息。
  /// Combines a tool item's status and available duration information.
  String _toolStatus(JsonMap item) {
    final status = _label(item['status']);
    final duration = item['durationMs'] is num
        ? ' · ${item['durationMs']} ms'
        : '';
    return status.isEmpty
        ? duration.replaceFirst(' · ', '')
        : '$status$duration';
  }

  /// 组合网页搜索查询文本和结果数量。
  /// Combines a web-search query with its result count.
  String _searchDetail(JsonMap item) {
    final query = _label(item['query']);
    final results = item['results'];
    final count = results is Iterable ? ' · ${results.length} 条结果' : '';
    return '$query$count'.trim();
  }

  /// 将任意协议值转换为去除首尾空白的显示文本。
  /// Converts any protocol value to trimmed display text.
  String _label(Object? value) => value?.toString().trim() ?? '';

  /// 分页加载并补齐恢复线程中尚未完整加载的历史内容。
  /// Paginates and hydrates historic content not fully loaded with a resumed thread.
  Future<JsonMap> _loadThreadHistory({
    required String threadId,
    required JsonMap resumeResult,
  }) async {
    final thread = resumeResult['thread'];
    final initialTurns = thread is Map && thread['turns'] is Iterable
        ? (thread['turns'] as Iterable)
              .whereType<Map>()
              .map(JsonMap.from)
              .toList()
        : <JsonMap>[];
    final turnsById = <String, JsonMap>{};
    for (final turn in initialTurns) {
      final id = turn['id']?.toString();
      if (id != null && id.isNotEmpty) turnsById[id] = turn;
    }
    var cursor = resumeResult['turnsBackwardsCursor']?.toString();
    var pageCount = 0;
    while (cursor != null && cursor.isNotEmpty && pageCount++ < 20) {
      final page = await _server.listThreadTurns(
        threadId: threadId,
        cursor: cursor,
        sortDirection: 'desc',
      );
      final data = page['data'];
      if (data is Iterable) {
        for (final rawTurn in data) {
          if (rawTurn is! Map) continue;
          final turn = JsonMap.from(rawTurn);
          final id = turn['id']?.toString();
          if (id != null && id.isNotEmpty) turnsById[id] = turn;
        }
      }
      final next = page['nextCursor']?.toString();
      cursor = next == null || next.isEmpty ? null : next;
    }
    final turns = turnsById.values.toList()
      ..sort((a, b) => _turnTimestamp(a).compareTo(_turnTimestamp(b)));
    var incompleteItemTurnCount = 0;
    for (final turn in turns) {
      final turnId = turn['id']?.toString();
      final itemsView = turn['itemsView'];
      if (turnId == null ||
          turnId.isEmpty ||
          (itemsView != 'notLoaded' && itemsView != 'summary')) {
        continue;
      }
      final hydrated = await _loadTurnItems(threadId: threadId, turnId: turnId);
      turn['items'] = hydrated.items;
      turn['itemsView'] = 'full';
      if (!hydrated.isComplete) incompleteItemTurnCount++;
    }
    return {
      'turns': turns,
      'incompleteTurnHistory': cursor != null,
      'incompleteItemTurnCount': incompleteItemTurnCount,
    };
  }

  /// 分页获取单个 turn 的项目，并报告是否在安全页数内完成。
  /// Paginates items for one turn and reports whether it completed within the page cap.
  Future<({List<JsonMap> items, bool isComplete})> _loadTurnItems({
    required String threadId,
    required String turnId,
  }) async {
    final items = <JsonMap>[];
    final seenCursors = <String>{};
    String? cursor;
    var pageCount = 0;
    do {
      final page = await _server.listThreadItems(
        threadId: threadId,
        turnId: turnId,
        cursor: cursor,
      );
      final data = page['data'];
      if (data is Iterable) {
        for (final rawEntry in data) {
          if (rawEntry is! Map || rawEntry['item'] is! Map) continue;
          items.add(JsonMap.from(rawEntry['item'] as Map));
        }
      }
      final next = page['nextCursor']?.toString();
      cursor = next == null || next.isEmpty ? null : next;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw StateError(
          'App Server repeated a thread item pagination cursor.',
        );
      }
    } while (cursor != null && ++pageCount < 20);
    return (items: items, isComplete: cursor == null);
  }

  /// 读取用于排序的 turn 时间戳，缺失时返回零。
  /// Reads the timestamp used for turn sorting, returning zero when absent.
  int _turnTimestamp(JsonMap turn) =>
      (turn['startedAt'] as num?)?.toInt() ??
      (turn['completedAt'] as num?)?.toInt() ??
      0;

  /// 从任务完成项中提取并记录文件变更。
  /// Extracts and records file changes from a completed-turn item.
  void _recordCompletedFileChange(Object? rawItem) {
    if (rawItem is! Map || rawItem['type']?.toString() != 'fileChange') {
      return;
    }
    _recordFileChanges(rawItem['changes']);
  }

  /// 合并服务器文件变更，供摘要、审查和右侧检查器使用。
  /// Merges server file changes for the summary, review, and inspector.
  void _recordFileChanges(Object? rawChanges) {
    if (rawChanges is! Iterable) return;
    var changed = false;
    for (final rawChange in rawChanges) {
      if (rawChange is! Map) continue;
      final change = CodexFileChange.fromJson(rawChange);
      if (change.path.isEmpty) continue;
      final previous = _fileChangesByPath[change.path];
      _fileChangesByPath[change.path] = change.diff.isEmpty && previous != null
          ? previous.copyWith(kind: change.kind)
          : change;
      changed = true;
    }
    if (changed) {
      // App Server 有时只提供文件路径和变更类型，Diff 会由工作区状态补齐。
      // App Server sometimes sends only the path and change kind; hydrate the Diff from the workspace.
      unawaited(_hydrateMissingFileChangeDiffs());
    }
  }

  /// 从当前工作区的只读 Git 状态补齐 App Server 未携带的文件 Diff。
  /// Hydrates file Diffs omitted by App Server from the current read-only Git workspace state.
  Future<void> _hydrateMissingFileChangeDiffs() async {
    final workspace = workspacePath;
    if (workspace == null || _disposed) return;
    final pending = fileChanges
        .where((change) => change.diff.trim().isEmpty)
        .toList(growable: false);
    if (pending.isEmpty) return;

    try {
      final status = await _gitProjectService.inspect(workspace);
      if (_disposed || workspacePath != workspace || !status.isRepository) {
        return;
      }
      final requests = <({CodexFileChange source, GitProjectChange target})>[];
      for (final source in pending) {
        GitProjectChange? target;
        for (final candidate in status.changes) {
          if (_sameWorkspaceChangePath(
                source.path,
                candidate.path,
                workspace,
              ) &&
              // A newly created file has no pre-existing user content, so the
              // /dev/null preview is safe. Tracked files may contain unrelated
              // edits from before this task and need turnDiff or a baseline.
              candidate.isUntracked) {
            target = candidate;
            break;
          }
        }
        if (target != null) requests.add((source: source, target: target));
      }
      if (requests.isEmpty) return;
      var hydrated = false;
      for (final request in requests) {
        if (_disposed || workspacePath != workspace) return;
        GitDiffPreview preview;
        try {
          preview = await _gitProjectService.readDiffPreview(
            workspace: workspace,
            change: request.target,
          );
        } catch (_) {
          continue;
        }
        final current = _fileChangesByPath[request.source.path];
        if (current != request.source || preview.content.trim().isEmpty) {
          continue;
        }
        _fileChangesByPath[request.source.path] = request.source.copyWith(
          diff: preview.content,
        );
        hydrated = true;
      }
      if (hydrated) {
        _scheduleConversationHistorySave();
        notifyListeners();
      }
    } catch (_) {
      // Git fallback is best-effort; the path remains visible even when the
      // workspace is not a repository or the file disappears before reading.
    }
  }

  /// 确保当前任务的文件变更尽可能包含只读工作区 Diff。
  /// Ensures the current task's file changes include a best-effort read-only workspace Diff.
  Future<void> ensureFileChangeDiffs() => _hydrateMissingFileChangeDiffs();

  /// Compares an App Server path with Git's workspace-relative path.
  bool _sameWorkspaceChangePath(
    String appServerPath,
    String gitPath,
    String workspace,
  ) {
    String normalize(String value) =>
        value.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');

    final source = normalize(appServerPath);
    final target = normalize(gitPath);
    if (source == target) return true;
    final root = normalize(workspace).replaceFirst(RegExp(r'/$'), '');
    return source == '$root/$target' || target == '$root/$source';
  }

  /// 规范化并保存当前任务的统一 Diff。
  /// Normalizes and stores the current turn's unified diff.
  void _updateTurnDiff(Object? rawDiff) {
    final diff = rawDiff?.toString() ?? '';
    turnDiff = diff.isEmpty ? null : diff;
  }

  /// 根据账户读取结果更新认证方式与账户显示信息。
  /// Updates authentication mode and account display data from an account response.
  void _updateAccount(JsonMap result) {
    final account = result['account'];
    final accountMap = account is Map ? JsonMap.from(account) : null;
    final authMode =
        result['authMode']?.toString() ?? accountMap?['type']?.toString();
    if (result.containsKey('requiresOpenaiAuth')) {
      requiresOpenaiAuth = result['requiresOpenaiAuth'] == true;
    }
    accountEmail = accountMap?['email']?.toString();
    accountPlan =
        result['planType']?.toString() ?? accountMap?['planType']?.toString();
    authStatus = switch (authMode) {
      'chatgpt' => AuthStatus.chatgpt,
      'apikey' || 'apiKey' => AuthStatus.apiKey,
      null || 'null' => AuthStatus.signedOut,
      _ => AuthStatus.external,
    };
  }

  /// 加载本地运行时路径、新任务模型、推理强度和审批模式偏好。
  /// Loads local runtime-path, new-task model, reasoning-effort, and approval-mode preferences.
  Future<void> _loadRuntimeConfiguration() async {
    try {
      final values = await Future.wait<Object?>([
        _runtimeConfigurationStore.readExecutable(),
        _runtimeConfigurationStore.readReasoningEffort(),
        _runtimeConfigurationStore.readModel(),
        _runtimeConfigurationStore.readPinnedWorkspaces(),
        _runtimeConfigurationStore.readApprovalMode(),
        _runtimeConfigurationStore.readScheduledTasks(),
      ]);
      final executable = values[0] as String?;
      if (executable != null && executable.trim().isNotEmpty) {
        _server.setExecutable(executable);
      }
      reasoningEffort = ReasoningEffort.fromConfigValue(values[1] as String?);
      if (reasoningEffort != ReasoningEffort.defaultValue) {
        reasoningEffortOptions = [
          ReasoningEffort.defaultValue,
          reasoningEffort,
        ];
      }
      selectedModelId = _nonEmptyConfigString(values[2] as String?);
      _pinnedWorkspacePaths
        ..clear()
        ..addAll(values[3] as Set<String>);
      if (!_approvalModeChangedBeforeLoad) {
        approvalMode = approvalModeFromStorageValue(values[4] as String?);
      }
      _scheduledTasks
        ..clear()
        ..addAll(values[5] as List<ScheduledTask>);
      _scheduledTasks.sort((left, right) => left.runAt.compareTo(right.runAt));
      for (final task in _scheduledTasks) {
        _armScheduledTask(task);
      }
    } catch (error) {
      runtimeError = '无法读取已保存的运行时配置：${_messageOf(error)}';
    }
  }

  Future<void> _saveScheduledTasks() =>
      _runtimeConfigurationStore.saveScheduledTasks(_scheduledTasks);

  /// Starts one timer per saved task. Overdue items are dispatched promptly
  /// after launch; a task is removed only after it has been handed to Codex.
  void _armScheduledTask(ScheduledTask task) {
    _scheduledTaskTimers.remove(task.id)?.cancel();
    final delay = task.runAt.difference(DateTime.now());
    _scheduledTaskTimers[task.id] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_dispatchScheduledTask(task.id)),
    );
  }

  Future<void> _dispatchScheduledTask(String id) async {
    _scheduledTaskTimers.remove(id)?.cancel();
    final task = _scheduledTasks.where((value) => value.id == id).firstOrNull;
    if (task == null || _disposed) return;
    // A live turn must not be replaced by unattended work. Keep the task and
    // retry after a short delay, preserving the user's currently running task.
    if (status == RuntimeStatus.running) {
      _scheduledTaskTimers[id] = Timer(
        const Duration(minutes: 1),
        () => unawaited(_dispatchScheduledTask(id)),
      );
      return;
    }
    if (task.workspacePath != workspacePath) {
      final switched = await selectWorkspaceAndReconnect(task.workspacePath);
      // Selecting a different workspace waits for runtime teardown and
      // startup. The user can cancel the task during that await, so never let
      // a stale dispatch create a thread or schedule another retry.
      if (_disposed || !_isScheduledTaskPending(task)) return;
      if (!switched || _disposed || workspacePath != task.workspacePath) {
        _scheduledTaskTimers[id] = Timer(
          const Duration(minutes: 1),
          () => unawaited(_dispatchScheduledTask(id)),
        );
        return;
      }
    }
    if (status != RuntimeStatus.ready) {
      _scheduledTaskTimers[id] = Timer(
        const Duration(minutes: 1),
        () => unawaited(_dispatchScheduledTask(id)),
      );
      return;
    }
    createThread();
    final sent = await sendPrompt(task.prompt);
    if (!sent) {
      _scheduledTaskTimers[id] = Timer(
        const Duration(minutes: 1),
        () => unawaited(_dispatchScheduledTask(id)),
      );
      return;
    }
    _scheduledTasks.removeWhere((value) => value.id == id);
    try {
      await _saveScheduledTasks();
    } catch (error) {
      lastError = '已安排任务已发送，但清理记录失败：${_messageOf(error)}';
      _add(TimelineKind.error, '已安排任务清理失败', lastError!);
    }
    if (!_disposed) notifyListeners();
  }

  bool _isScheduledTaskPending(ScheduledTask task) =>
      _scheduledTasks.any((candidate) => candidate.id == task.id);

  /// 构建新线程的可选推理配置；模型为空时由 App Server 跟随 Codex 配置。
  /// Builds optional reasoning configuration for a new thread; a null model follows Codex configuration.
  JsonMap? _newThreadConfig() {
    final effort = reasoningEffort.configValue;
    final config = <String, dynamic>{
      if (effort != null &&
          _supportsReasoningEffort(_newThreadModelId, reasoningEffort))
        'model_reasoning_effort': effort,
    };
    return config.isEmpty ? null : config;
  }

  String? get _modelOverrideForNewThread {
    final selected = selectedModelId;
    return selected != null &&
            modelOptions.any((option) => option.id == selected)
        ? selected
        : null;
  }

  String? get _newThreadModelId =>
      _modelOverrideForNewThread ??
      _configuredModelId ??
      _catalogDefaultModelId;

  /// 判断指定或默认模型是否支持给定的推理强度。
  /// Determines whether the specified or default model supports a reasoning effort.
  bool _supportsReasoningEffort(String? modelId, ReasoningEffort effort) {
    return modelId != null &&
        (_reasoningEffortsByModel[modelId]?.contains(effort) ?? false);
  }

  /// 从模型列表刷新可用推理强度，并降级失效的已保存选择。
  /// Refreshes available reasoning efforts from models and downgrades an invalid saved choice.
  Future<void> _refreshReasoningEffortCapabilities() async {
    try {
      final models = await _server.listModels();
      final capabilities = <String, Set<ReasoningEffort>>{};
      final optionsById = <String, CodexModelOption>{};
      String? defaultModelId;
      for (final model in models) {
        final id = _nonEmptyConfigString(model['id'] ?? model['model']);
        if (id == null) continue;
        final options = <ReasoningEffort>{};
        final supported = model['supportedReasoningEfforts'];
        if (supported is Iterable) {
          for (final rawOption in supported) {
            if (rawOption is! Map) continue;
            final effort = ReasoningEffort.fromConfigValue(
              rawOption['reasoningEffort']?.toString(),
            );
            if (effort != ReasoningEffort.defaultValue) options.add(effort);
          }
        }
        capabilities[id] = options;
        final modelName = model['model']?.toString();
        if (modelName != null && modelName.isNotEmpty) {
          capabilities[modelName] = options;
        }
        final isDefault = model['isDefault'] == true;
        optionsById.putIfAbsent(
          id,
          () => CodexModelOption(
            id: id,
            displayName:
                _nonEmptyConfigString(model['displayName']) ?? modelName ?? id,
            description: _nonEmptyConfigString(model['description']) ?? '',
            isDefault: isDefault,
          ),
        );
        if (isDefault) defaultModelId ??= id;
      }
      _reasoningEffortsByModel = capabilities;
      modelOptions = List.unmodifiable(optionsById.values);
      modelCatalogError = null;
      _catalogDefaultModelId =
          defaultModelId ??
          (models.isEmpty
              ? null
              : (models.first['id'] ?? models.first['model'])?.toString());
      final savedModel = selectedModelId;
      if (savedModel != null && !optionsById.containsKey(savedModel)) {
        selectedModelId = null;
        _add(TimelineKind.system, '新任务模型已恢复为跟随配置', '已保存的模型当前不可用。');
        try {
          await _saveModelSelection(null);
        } catch (error) {
          _add(TimelineKind.error, '无法清除失效模型选择', _messageOf(error));
        }
      }
      final effortWasReset = _updateReasoningEffortOptions();
      if (effortWasReset) {
        try {
          await _saveReasoningEffort(ReasoningEffort.defaultValue);
        } catch (error) {
          _add(TimelineKind.error, '无法保存默认推理强度', _messageOf(error));
        }
      }
    } catch (error) {
      _reasoningEffortsByModel = const {};
      modelOptions = const [];
      _catalogDefaultModelId = null;
      modelCatalogError = '无法加载模型目录：${_messageOf(error)}';
      reasoningEffortOptions = [
        ReasoningEffort.defaultValue,
        if (reasoningEffort != ReasoningEffort.defaultValue) reasoningEffort,
      ];
      _add(
        TimelineKind.error,
        '无法加载模型目录',
        selectedModelId == null &&
                reasoningEffort == ReasoningEffort.defaultValue
            ? '仍可跟随 Codex 配置创建任务。'
            : '当前模型或推理强度选择无法验证，请恢复为跟随配置和默认强度后重试。',
      );
    }
  }

  /// 根据后续新任务模型刷新推理强度选项；返回是否将已选强度恢复为默认。
  /// Refreshes reasoning-effort options for the new-task model and returns whether the selected effort was reset.
  bool _updateReasoningEffortOptions() {
    final availableEfforts = [...?_reasoningEffortsByModel[_newThreadModelId]];
    reasoningEffortOptions = [
      ReasoningEffort.defaultValue,
      ...availableEfforts,
    ];
    if (reasoningEffortOptions.contains(reasoningEffort)) return false;
    reasoningEffort = ReasoningEffort.defaultValue;
    _add(TimelineKind.system, '推理强度已恢复为默认', '所选的新任务模型不支持此前的推理强度。');
    return true;
  }

  /// 串行保存推理强度，以确保较新的选择不会被旧写入覆盖。
  /// Serializes reasoning-effort writes so an older write cannot overwrite a newer choice.
  Future<void> _saveReasoningEffort(ReasoningEffort value) {
    final previousSave = _reasoningEffortSave;
    final nextSave = () async {
      try {
        await previousSave;
      } catch (_) {
        // A previous write failure must not prevent a newer choice from saving.
      }
      await _runtimeConfigurationStore.saveReasoningEffort(value.configValue);
    }();
    _reasoningEffortSave = nextSave;
    return nextSave;
  }

  /// 串行保存新任务模型，避免较早写入覆盖用户较新的选择。
  /// Serializes new-task model writes so an older save cannot overwrite a newer selection.
  Future<void> _saveModelSelection(String? value) {
    final previousSave = _modelSelectionSave;
    final nextSave = () async {
      try {
        await previousSave;
      } catch (_) {
        // A previous write failure must not prevent a newer choice from saving.
      }
      await _runtimeConfigurationStore.saveModel(value);
    }();
    _modelSelectionSave = nextSave;
    return nextSave;
  }

  /// 串行保存审批模式，避免较早写入覆盖用户较新的选择。
  /// Serializes approval-mode writes so an older save cannot overwrite a newer selection.
  Future<void> _saveApprovalMode(ApprovalMode value) {
    final previousSave = _approvalModeSave;
    final nextSave = () async {
      try {
        await previousSave;
      } catch (_) {
        // A previous write failure must not prevent a newer choice from saving.
      }
      await _runtimeConfigurationStore.saveApprovalMode(value.name);
    }();
    _approvalModeSave = nextSave;
    return nextSave;
  }

  /// 将当前目录集合写回对应工作区记录；没有主目录时保持列表不变。
  /// Writes the current directory set back to its workspace record, leaving the list unchanged without a primary path.
  void _updateCurrentWorkspaceConfiguration() {
    final primary = workspacePath;
    if (primary == null) return;
    final existingIndex = _workspaceConfigurations.indexWhere(
      (candidate) => candidate.primaryPath == primary,
    );
    final existingName = existingIndex < 0
        ? null
        : _workspaceConfigurations[existingIndex].name;
    final existingId = existingIndex < 0
        ? _newWorkspaceProjectId()
        : _workspaceConfigurations[existingIndex].id ??
              _newWorkspaceProjectId();
    final configuration = WorkspaceConfiguration(
      id: existingId,
      primaryPath: primary,
      additionalPaths: _additionalWorkspacePaths
          .where((path) => path != primary)
          .toList(growable: false),
      name: existingName,
    );
    if (existingIndex < 0) {
      _workspaceConfigurations.add(configuration);
    } else {
      _workspaceConfigurations[existingIndex] = configuration;
    }
  }

  /// 串行保存完整工作区快照，并同步旧版当前附加目录偏好以支持平滑迁移。
  /// Serializes complete workspace snapshots while mirroring the current legacy additional-root preference for migration.
  Future<void> _saveAdditionalWorkspacePaths() {
    _updateCurrentWorkspaceConfiguration();
    final snapshot = List<String>.unmodifiable(_additionalWorkspacePaths);
    final workspaceSnapshot = List<WorkspaceConfiguration>.unmodifiable(
      _workspaceConfigurations.map(
        (configuration) => WorkspaceConfiguration(
          id: configuration.id,
          primaryPath: configuration.primaryPath,
          additionalPaths: configuration.additionalPaths,
          name: configuration.name,
        ),
      ),
    );
    final previousSave = _workspaceRootsSave;
    final nextSave = () async {
      try {
        await previousSave;
      } catch (_) {
        // A previous write failure must not prevent a newer snapshot from saving.
      }
      await _runtimeConfigurationStore.saveWorkspaces(workspaceSnapshot);
      await _runtimeConfigurationStore.saveAdditionalWorkspaces(snapshot);
    }();
    _workspaceRootsSave = nextSave;
    return nextSave;
  }

  @visibleForTesting
  /// 刷新模型能力，供测试验证推理强度选择。
  /// Refreshes model capabilities for reasoning-effort tests.
  Future<void> refreshReasoningEffortCapabilitiesForTesting() {
    return _refreshReasoningEffortCapabilities();
  }

  static String? _nonEmptyConfigString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// 从 `config/read` 的 origins 中找到字段来源；不读取或保留任何凭据内容。
  /// Finds a field origin from `config/read`; no credential content is read or retained.
  static String? _configurationOriginLabel(Object? rawOrigins, String field) {
    if (rawOrigins is! Map) return null;
    Object? metadata = rawOrigins[field];
    if (metadata == null) {
      for (final entry in rawOrigins.entries) {
        final key = entry.key.toString();
        if (key == field ||
            key.endsWith('/$field') ||
            key.endsWith('.$field')) {
          metadata = entry.value;
          break;
        }
      }
    }
    if (metadata is! Map || metadata['name'] is! Map) return null;
    final source = metadata['name'] as Map;
    final type = source['type']?.toString();
    return switch (type) {
      'user' => _nonEmptyConfigString(source['file']) ?? '用户配置',
      'project' => switch (_nonEmptyConfigString(source['dotCodexFolder'])) {
        final folder? => '$folder/config.toml',
        null => '项目配置',
      },
      'system' || 'legacyManagedConfigTomlFromFile' =>
        _nonEmptyConfigString(source['file']) ?? '系统配置',
      'packagedDefaults' => 'Codex 内置默认值',
      'sessionFlags' => '运行时启动参数',
      'mdm' => '设备管理配置',
      'enterpriseManaged' => _nonEmptyConfigString(source['name']) ?? '组织管理配置',
      'legacyManagedConfigTomlFromMdm' => '设备管理配置',
      _ => null,
    };
  }

  /// 校验并规范化一个已保存工作区，过滤失效、重复或与主目录相同的附加路径。
  /// Validates and canonicalizes a saved workspace, filtering missing, duplicate, or primary-matching additional paths.
  Future<WorkspaceConfiguration?> _restoreWorkspaceConfiguration(
    WorkspaceConfiguration stored,
  ) async {
    final primaryDirectory = Directory(stored.primaryPath);
    if (stored.primaryPath.isEmpty || !await primaryDirectory.exists()) {
      return null;
    }
    try {
      final primaryPath = await primaryDirectory.resolveSymbolicLinks();
      if (await _isSystemTemporaryDirectory(primaryPath)) return null;
      final additionalPaths = <String>[];
      for (final storedAdditional in stored.additionalPaths) {
        final directory = Directory(storedAdditional);
        if (!await directory.exists()) continue;
        final canonicalPath = await directory.resolveSymbolicLinks();
        if (!await _isSystemTemporaryDirectory(canonicalPath) &&
            canonicalPath != primaryPath &&
            !additionalPaths.contains(canonicalPath)) {
          additionalPaths.add(canonicalPath);
        }
      }
      return WorkspaceConfiguration(
        id: stored.id ?? _newWorkspaceProjectId(),
        primaryPath: primaryPath,
        additionalPaths: additionalPaths,
        name: stored.name,
      );
    } on FileSystemException {
      return null;
    }
  }

  /// 恢复全部有效工作区及上次活动项，并将旧版单工作区偏好迁移为可切换列表。
  /// Restores all valid workspaces and the last active entry, migrating legacy single-workspace preferences to a switchable list.
  Future<void> _loadWorkspace() async {
    try {
      final storedPath = await _runtimeConfigurationStore.readWorkspace();
      String? restoredActivePath;
      if (storedPath != null && storedPath.trim().isNotEmpty) {
        final directory = Directory(storedPath.trim());
        if (!await directory.exists()) {
          await _runtimeConfigurationStore.clearWorkspace();
          _add(TimelineKind.system, '已清除无效项目记录', storedPath.trim());
        } else {
          final canonicalPath = await directory.resolveSymbolicLinks();
          if (await _isSystemTemporaryDirectory(canonicalPath)) {
            await _runtimeConfigurationStore.clearWorkspace();
            _add(TimelineKind.system, '已清除系统临时目录项目', canonicalPath);
          } else {
            restoredActivePath = canonicalPath;
            if (workspacePath == null) {
              workspacePath = canonicalPath;
              _add(TimelineKind.system, '已恢复上次项目', canonicalPath);
            }
          }
        }
      }

      final storedConfigurations = await _runtimeConfigurationStore
          .readWorkspaces();
      final restoredConfigurations = <WorkspaceConfiguration>[];
      for (final stored in storedConfigurations) {
        final restored = await _restoreWorkspaceConfiguration(stored);
        if (restored != null &&
            !restoredConfigurations.any(
              (existing) => existing.primaryPath == restored.primaryPath,
            )) {
          restoredConfigurations.add(restored);
          if (stored.id == null || stored.id!.isEmpty) {
            _legacyWorkspaceHistoryPaths.add(restored.primaryPath);
          }
        }
      }
      final validWorkspacePaths = restoredConfigurations
          .map((workspace) => workspace.primaryPath)
          .toSet();
      final hadStalePins = _pinnedWorkspacePaths.any(
        (path) => !validWorkspacePaths.contains(path),
      );
      _pinnedWorkspacePaths.removeWhere(
        (path) => !validWorkspacePaths.contains(path),
      );
      if (hadStalePins) {
        await _runtimeConfigurationStore.savePinnedWorkspaces(
          _pinnedWorkspacePaths,
        );
      }

      final legacyAdditional = await _runtimeConfigurationStore
          .readAdditionalWorkspaces();
      var activePath = workspacePath ?? restoredActivePath;
      if (activePath == null && restoredConfigurations.isNotEmpty) {
        activePath = restoredConfigurations.first.primaryPath;
        workspacePath = activePath;
        await _runtimeConfigurationStore.saveWorkspace(activePath);
        _add(TimelineKind.system, '已恢复可用工作区', activePath);
      }

      if (activePath != null &&
          !restoredConfigurations.any(
            (configuration) => configuration.primaryPath == activePath,
          )) {
        final migrated = await _restoreWorkspaceConfiguration(
          WorkspaceConfiguration(
            primaryPath: activePath,
            additionalPaths: legacyAdditional,
          ),
        );
        if (migrated != null) {
          restoredConfigurations.add(migrated);
          _legacyWorkspaceHistoryPaths.add(migrated.primaryPath);
        }
      }

      _workspaceConfigurations
        ..clear()
        ..addAll(restoredConfigurations);
      final activeIndex = activePath == null
          ? -1
          : _workspaceConfigurations.indexWhere(
              (configuration) => configuration.primaryPath == activePath,
            );
      _additionalWorkspacePaths
        ..clear()
        ..addAll(
          activeIndex < 0
              ? const <String>[]
              : _workspaceConfigurations[activeIndex].additionalPaths,
        );
      _workspaceProjectId = activeIndex < 0
          ? null
          : _workspaceConfigurations[activeIndex].id;

      final storedJson = jsonEncode(
        storedConfigurations
            .map((configuration) => configuration.toJson())
            .toList(),
      );
      final restoredJson = jsonEncode(
        restoredConfigurations
            .map((configuration) => configuration.toJson())
            .toList(),
      );
      if (storedJson != restoredJson) {
        await _runtimeConfigurationStore.saveWorkspaces(restoredConfigurations);
      }
      if (!listEquals(legacyAdditional, _additionalWorkspacePaths)) {
        await _saveAdditionalWorkspacePaths();
      }
      unawaited(refreshInactiveWorkspaceTaskLists());
    } catch (error) {
      lastError = '无法恢复上次项目：${_messageOf(error)}';
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  /// 等待项目路径恢复后加载对应的本地对话历史。
  /// Waits for workspace restoration, then loads its local conversation history.
  Future<void> _loadConversationHistory() async {
    await _workspaceLoad;
    final workspace = workspacePath;
    if (workspace != null) await _restoreConversationHistory(workspace);
  }

  /// 将指定项目的已缓存线程、时间线和 Diff 恢复到界面状态。
  /// Restores a workspace's cached threads, timeline, and diff into UI state.
  Future<void> _restoreConversationHistory(String workspace) async {
    try {
      final historyKey = _historyKeyFor(workspace);
      var snapshot = await _conversationHistoryStore.read(historyKey);
      if (snapshot == null && historyKey != workspace) {
        snapshot = await _conversationHistoryStore.read(workspace);
        // Persist the recovered legacy snapshot immediately. Previously this
        // was deferred until another history change, so a restart could make
        // an existing project's task list appear empty again.
        if (snapshot != null) {
          await _conversationHistoryStore.save(
            workspace: historyKey,
            snapshot: snapshot,
          );
        }
      }
      if (_disposed || workspacePath != workspace || snapshot == null) return;
      threads = snapshot.threads;
      archivedThreads = snapshot.archivedThreads;
      _pinnedThreadIds
        ..clear()
        ..addAll(snapshot.pinnedThreadIds);
      if (snapshot.entries.isNotEmpty) {
        _entries
          ..clear()
          ..addAll(snapshot.entries);
      }
      _fileChangesByPath
        ..clear()
        ..addEntries(
          snapshot.fileChanges.map((change) => MapEntry(change.path, change)),
        );
      turnDiff = snapshot.turnDiff;
      activeThreadId = snapshot.activeThreadId;
      _ownedThreadIds
        ..clear()
        ..addAll(snapshot.ownedThreadIds);
      _threadHistoryInitialized = snapshot.historyInitialized;
      _activeThreadAttached = false;
      // Cached history may predate file-level Diff support.
      // Hydrate safe untracked-file previews after restoring the snapshot.
      unawaited(_hydrateMissingFileChangeDiffs());
    } catch (error) {
      _add(TimelineKind.error, '无法读取本地历史', _messageOf(error));
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  @visibleForTesting
  /// 等待所有启动阶段的本地配置与历史恢复完成。
  /// Waits for all startup local configuration and history restoration to finish.
  Future<void> waitForInitialConfiguration() {
    return Future.wait([_runtimeLoad, _workspaceLoad, _historyLoad]);
  }

  @visibleForTesting
  /// 立即保存当前历史，供测试验证持久化行为。
  /// Immediately saves current history for persistence tests.
  Future<void> saveConversationHistoryForTesting() {
    return _saveConversationHistory();
  }

  /// 探测 Codex CLI 并可选地在开始和结束时通知界面。
  /// Probes the Codex CLI and optionally notifies the UI at start and finish.
  Future<CodexRuntimeProbe> _inspectRuntime({required bool notify}) async {
    runtimeChecking = true;
    if (notify && !_disposed) notifyListeners();
    final probe = await _server.probe();
    runtimeProbe = probe;
    runtimeError = probe.isAvailable ? null : probe.error;
    runtimeChecking = false;
    if (notify && !_disposed) notifyListeners();
    return probe;
  }

  /// 将已脱敏运行时文本加入有上限的内存诊断缓冲区。
  /// Adds redacted runtime text to the bounded in-memory diagnostic buffer.
  void _recordRuntimeLog(String message, {RuntimeLogLevel? level}) {
    final value = CodexAppServer.redactDiagnosticText(message).trim();
    if (value.isEmpty) return;
    _runtimeLogs.add(
      level == null
          ? RuntimeLogEntry.fromMessage(message: value)
          : RuntimeLogEntry(
              message: value,
              level: level,
              createdAt: DateTime.now(),
            ),
    );
    if (_runtimeLogs.length > _maximumRuntimeLogEntries) {
      _runtimeLogs.removeRange(
        0,
        _runtimeLogs.length - _maximumRuntimeLogEntries,
      );
    }
  }

  /// 执行一个插件配置变更，避免在任务执行中修改运行时配置。
  /// Runs a plugin configuration change while avoiding runtime changes mid-turn.
  Future<void> _runPluginAction(
    Future<void> Function() action,
    String successMessage, {
    required String progressMessage,
    String? targetId,
  }) async {
    if (status == RuntimeStatus.running) {
      pluginsError = '请等待当前任务完成后再变更插件。';
      if (!_disposed) notifyListeners();
      return;
    }
    if (pluginSaving) return;
    pluginSaving = true;
    pluginsError = null;
    pluginActionProgress = progressMessage;
    if (!pluginRuntimeRestartRequired) pluginActionResult = null;
    pluginActionTargetId = targetId;
    if (!_disposed) notifyListeners();
    try {
      await action();
      pluginRuntimeRestartRequired = true;
      pluginActionResult = '$successMessage。应用会自动重启运行时，使变更用于后续新任务。';
      _add(TimelineKind.system, successMessage, '应用会在安全状态下自动重连，以加载最新插件。');
      try {
        plugins = await _pluginStore.listPlugins();
        marketplaces = await _pluginStore.listMarketplaces();
      } catch (error) {
        pluginsError = '操作已完成，但刷新插件状态失败：${_messageOf(error)}';
      }
      if (workspacePath != null && status != RuntimeStatus.starting) {
        await reconnectRuntime();
        if (status == RuntimeStatus.failed) {
          pluginActionResult = '$successMessage，但自动重连失败：$lastError';
        }
      }
    } catch (error) {
      final actionLabel = progressMessage.replaceFirst(RegExp(r'…$'), '');
      pluginsError = '$actionLabel失败：${_messageOf(error)}';
    } finally {
      pluginSaving = false;
      pluginActionProgress = null;
      pluginActionTargetId = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// 取消流式更新计时器并清除 Agent 条目索引。
  /// Cancels streaming timers and clears the Agent-entry index.
  void _clearStreamingState() {
    _agentEntryIndexByItem.clear();
    _completedCommandItemIds.clear();
    activeTurnId = null;
    _activeTurnStartedAt = null;
    _activeCommand = null;
    _activeCommandItemId = null;
    activeTaskPlan = null;
    _deltaNotificationTimer?.cancel();
    _deltaNotificationTimer = null;
  }

  /// 合并短时间内连续发生的历史变更，延迟执行一次保存。
  /// Coalesces nearby history changes into one delayed save.
  void _scheduleConversationHistorySave() {
    if (workspacePath == null || _disposed || _historySaveTimer != null) return;
    _historySaveTimer = Timer(const Duration(milliseconds: 500), () {
      _historySaveTimer = null;
      unawaited(_saveConversationHistory());
    });
  }

  /// 快照当前工作区状态并串行加密写入本地历史缓存。
  /// Snapshots workspace state and serially writes it to the encrypted local history cache.
  Future<void> _saveConversationHistory() async {
    final workspace = workspacePath;
    if (workspace == null || _disposed) return;
    _historySaveTimer?.cancel();
    _historySaveTimer = null;
    final snapshot = _conversationHistorySnapshot();
    final previousSave = _historySave;
    final nextSave = () async {
      try {
        await previousSave;
      } catch (_) {
        // A failed older save must not prevent a newer snapshot from writing.
      }
      await _conversationHistoryStore.save(
        workspace: _historyKeyFor(workspace),
        snapshot: snapshot,
      );
    }();
    _historySave = nextSave;
    try {
      await nextSave;
      _historySaveFailed = false;
    } catch (error) {
      if (!_disposed && !_historySaveFailed) {
        _historySaveFailed = true;
        _entries.add(_entry(TimelineKind.error, '无法保存本地历史', _messageOf(error)));
        notifyListeners();
      }
    }
  }

  /// 捕获当前项目的线程、置顶状态、时间线和文件变更，用于持久化或导出。
  /// Captures current workspace tasks, pins, timeline, and file changes for persistence or export.
  ConversationHistorySnapshot _conversationHistorySnapshot() {
    return ConversationHistorySnapshot(
      threads: List.of(threads),
      archivedThreads: List.of(archivedThreads),
      entries: List.of(entries),
      fileChanges: List.of(fileChanges),
      pinnedThreadIds: Set.of(_pinnedThreadIds),
      turnDiff: turnDiff,
      activeThreadId: activeThreadId,
      ownedThreadIds: Set.of(_ownedThreadIds),
      historyInitialized: _threadHistoryInitialized,
    );
  }

  /// 清空当前任务的文件变更集合和统一 Diff。
  /// Clears the current task's file-change collection and unified diff.
  void _clearFileChanges() {
    _fileChangesByPath.clear();
    turnDiff = null;
  }

  /// Caches the current attached task before switching to another task.
  /// 切换任务前缓存当前已连接任务的页面状态。
  void _cacheActiveThreadView() {
    final id = activeThreadId;
    if (id == null || !_activeThreadAttached) return;
    _threadViewCache
      ..remove(id)
      ..[id] = _currentThreadViewSnapshot();
    while (_threadViewCache.length > _maximumThreadViewCacheEntries) {
      _threadViewCache.remove(_threadViewCache.keys.first);
    }
  }

  /// Promotes a cached task page so recently revisited tasks remain retained.
  /// 提升刚访问的任务页面，优先保留近期重新打开的任务。
  _ThreadViewSnapshot? _cachedThreadView(String id) {
    final snapshot = _threadViewCache.remove(id);
    if (snapshot != null) _threadViewCache[id] = snapshot;
    return snapshot;
  }

  _ThreadViewSnapshot _currentThreadViewSnapshot() => _ThreadViewSnapshot(
    entries: List.unmodifiable(_entries),
    fileChanges: List.unmodifiable(fileChanges),
    turnDiff: turnDiff,
  );

  /// Clears any previous task content before first-time history hydration.
  /// 首次加载任务历史前清除前一任务内容，避免在失败时串到新任务。
  void _clearThreadTimelineForRestoration() {
    _entries.clear();
    _clearFileChanges();
  }

  /// Restores a cached task view into the shared controller state.
  /// 将缓存的任务页面恢复到共享控制器状态。
  void _restoreThreadView(_ThreadViewSnapshot snapshot) {
    _entries
      ..clear()
      ..addAll(snapshot.entries);
    _fileChangesByPath
      ..clear()
      ..addEntries(
        snapshot.fileChanges.map((change) => MapEntry(change.path, change)),
      );
    turnDiff = snapshot.turnDiff;
  }

  /// 保留欢迎项并清空与当前线程相关的时间线内容。
  /// Retains the welcome item while clearing timeline content for the current thread.
  void _resetConversationTimeline() {
    _clearFileChanges();
    if (_entries.isEmpty) return;
    final welcome = _entries.first;
    _entries
      ..clear()
      ..add(welcome);
  }

  /// 使正在进行的线程刷新结果失效，并重置刷新状态。
  /// Invalidates in-flight thread refreshes and resets refresh state.
  void _invalidateThreadRefreshes() {
    _threadRefreshEpoch++;
    _threadRefreshRequest++;
    _archivedThreadRefreshRequest++;
    threadsLoading = false;
    threadsError = null;
    archivedThreadsLoading = false;
    archivedThreadsError = null;
  }

  /// 判断活跃线程刷新结果是否仍属于当前运行时与项目。
  /// Determines whether an active-thread refresh still belongs to this runtime and workspace.
  bool _isCurrentThreadRefresh(int request, int epoch, String workspace) {
    return !_disposed &&
        request == _threadRefreshRequest &&
        epoch == _threadRefreshEpoch &&
        workspacePath == workspace &&
        _server.isRunning;
  }

  /// 判断归档线程刷新结果是否仍属于当前运行时与项目。
  /// Determines whether an archived-thread refresh still belongs to this runtime and workspace.
  bool _isCurrentArchivedThreadRefresh(
    int request,
    int epoch,
    String workspace,
  ) {
    return !_disposed &&
        request == _archivedThreadRefreshRequest &&
        epoch == _threadRefreshEpoch &&
        workspacePath == workspace &&
        _server.isRunning;
  }

  /// 合并高频流式文本事件，避免每个增量都触发一次重建。
  /// Coalesces high-frequency text events to avoid rebuilding for every delta.
  void _scheduleDeltaNotification() {
    if (_deltaNotificationTimer != null || _disposed) return;
    _deltaNotificationTimer = Timer(const Duration(milliseconds: 50), () {
      _deltaNotificationTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  /// 去除 Dart 状态错误前缀，返回适合用户展示的错误文本。
  /// Removes the Dart state-error prefix for user-displayable error text.
  String _messageOf(Object error) =>
      error.toString().replaceFirst('Bad state: ', '');

  /// 系统临时目录根会被系统随时清理，不能作为稳定的 Codex 项目。
  /// The system temporary-directory root is not a stable Codex project.
  Future<bool> _isSystemTemporaryDirectory(String canonicalPath) async {
    try {
      return canonicalPath == await Directory.systemTemp.resolveSymbolicLinks();
    } on FileSystemException {
      return false;
    }
  }

  /// Creates a local project identity without tying history to its directory.
  String _newWorkspaceProjectId() =>
      'project-${DateTime.now().microsecondsSinceEpoch}-${_workspaceConfigurations.length}';

  String _historyKeyFor(String workspace) => _workspaceProjectId ?? workspace;

  /// 创建带有当前时间戳的时间线条目。
  /// Creates a timeline entry stamped with the current time.
  TimelineEntry _entry(
    TimelineKind kind,
    String title,
    String detail, {
    List<String> imagePaths = const [],
  }) {
    return TimelineEntry(
      kind: kind,
      title: title,
      detail: detail,
      createdAt: DateTime.now(),
      imagePaths: imagePaths,
    );
  }

  /// 追加时间线条目并安排本地历史保存。
  /// Appends a timeline entry and schedules local history persistence.
  void _add(
    TimelineKind kind,
    String title,
    String detail, {
    List<String> imagePaths = const [],
  }) {
    _entries.add(_entry(kind, title, detail, imagePaths: imagePaths));
    _scheduleConversationHistorySave();
  }

  /// 释放计时器、事件订阅和 App Server 资源，并尝试保存最后的历史快照。
  /// Releases timers, event subscriptions, and App Server resources, while attempting a final history save.
  @override
  void dispose() {
    _historySaveTimer?.cancel();
    _runtimeReconnectTimer?.cancel();
    _runtimeReconnectTimer = null;
    for (final timer in _scheduledTaskTimers.values) {
      timer.cancel();
    }
    _scheduledTaskTimers.clear();
    _runtimeConnectionEpoch++;
    unawaited(_saveConversationHistory());
    _disposed = true;
    _clearStreamingState();
    unawaited(_eventSubscription?.cancel());
    unawaited(_server.dispose());
    super.dispose();
  }
}
