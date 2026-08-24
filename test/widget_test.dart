import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:chatgpt/src/app.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/codex_hover_popup.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/domain/task_plan.dart';
import 'package:chatgpt/src/domain/scheduled_task.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/presentation/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:chatgpt/src/services/codex_plugin_store.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:chatgpt/src/services/local_session_thread_store.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

class _FakeRuntimeConfigurationStore extends RuntimeConfigurationStore {
  String? workspace;
  String? savedWorkspace;
  List<String> additionalWorkspaces = [];
  List<String>? savedAdditionalWorkspaces;
  List<WorkspaceConfiguration> workspaces = [];
  List<WorkspaceConfiguration>? savedWorkspaces;
  String? reasoningEffort;
  String? savedReasoningEffort;
  String? model;
  String? savedModel;
  String? approvalMode;
  String? savedApprovalMode;
  bool clearedWorkspace = false;
  Set<String> pinnedWorkspaces = {};
  Set<String>? savedPinnedWorkspaces;
  List<ScheduledTask> scheduledTasks = [];
  List<ScheduledTask>? savedScheduledTasks;

  /// 模拟未保存自定义 CLI 路径。
  /// Simulates no saved custom CLI path.
  @override
  Future<String?> readExecutable() async => null;

  /// 返回测试预设的项目路径。
  /// Returns the test-configured workspace path.
  @override
  Future<String?> readWorkspace() async => workspace;

  /// 在内存中保存项目路径，便于断言持久化结果。
  /// Saves the workspace path in memory for persistence assertions.
  @override
  Future<void> saveWorkspace(String value) async {
    savedWorkspace = value;
    workspace = value;
  }

  /// 清空内存项目路径并标记清理操作。
  /// Clears the in-memory workspace path and records the clear operation.
  @override
  Future<void> clearWorkspace() async {
    clearedWorkspace = true;
    workspace = null;
  }

  /// 返回测试预设的附加工作区目录。
  /// Returns test-configured additional workspace directories.
  @override
  Future<List<String>> readAdditionalWorkspaces() async =>
      List.of(additionalWorkspaces);

  /// 在内存中保存附加工作区目录，便于断言持久化结果。
  /// Saves additional workspace directories in memory for persistence assertions.
  @override
  Future<void> saveAdditionalWorkspaces(List<String> workspaces) async {
    savedAdditionalWorkspaces = List.of(workspaces);
    additionalWorkspaces = List.of(workspaces);
  }

  /// 返回测试预设的可切换工作区列表。
  /// Returns the test-configured switchable workspace list.
  @override
  Future<List<WorkspaceConfiguration>> readWorkspaces() async => workspaces
      .map(
        (workspace) => WorkspaceConfiguration(
          id: workspace.id,
          primaryPath: workspace.primaryPath,
          additionalPaths: workspace.additionalPaths,
        ),
      )
      .toList(growable: false);

  /// 在内存中保存完整工作区列表，便于验证迁移和切换。
  /// Saves the complete workspace list in memory for migration and switching assertions.
  @override
  Future<void> saveWorkspaces(
    List<WorkspaceConfiguration> configurations,
  ) async {
    final snapshot = configurations
        .map(
          (workspace) => WorkspaceConfiguration(
            id: workspace.id,
            primaryPath: workspace.primaryPath,
            additionalPaths: workspace.additionalPaths,
          ),
        )
        .toList(growable: false);
    savedWorkspaces = snapshot;
    workspaces = snapshot;
  }

  @override
  Future<Set<String>> readPinnedWorkspaces() async => Set.of(pinnedWorkspaces);

  @override
  Future<void> savePinnedWorkspaces(Iterable<String> paths) async {
    savedPinnedWorkspaces = paths.toSet();
    pinnedWorkspaces = paths.toSet();
  }

  @override
  Future<List<ScheduledTask>> readScheduledTasks() async =>
      List.of(scheduledTasks);

  @override
  Future<void> saveScheduledTasks(Iterable<ScheduledTask> tasks) async {
    savedScheduledTasks = tasks.toList(growable: false);
    scheduledTasks = List.of(savedScheduledTasks!);
  }

  /// 返回测试预设的推理强度。
  /// Returns the test-configured reasoning effort.
  @override
  Future<String?> readReasoningEffort() async => reasoningEffort;

  /// 在内存中保存推理强度，便于断言更新结果。
  /// Saves reasoning effort in memory for update assertions.
  @override
  Future<void> saveReasoningEffort(String? value) async {
    savedReasoningEffort = value;
    reasoningEffort = value;
  }

  /// 返回测试预设的新任务模型；`null` 表示跟随 Codex 配置。
  /// Returns the test-configured model for new tasks; `null` means follow Codex configuration.
  @override
  Future<String?> readModel() async => model;

  /// 在内存中保存新任务模型，便于断言模型切换持久化。
  /// Saves the new-task model in memory so model-selection persistence can be asserted.
  @override
  Future<void> saveModel(String? value) async {
    savedModel = value;
    model = value;
  }

  /// 返回测试预设的审批模式；`null` 表示请求批准。
  /// Returns the test-configured approval mode; `null` means request approval.
  @override
  Future<String?> readApprovalMode() async => approvalMode;

  /// 在内存中保存审批模式，便于验证重启后的恢复行为。
  /// Saves approval mode in memory to verify restoration after restart.
  @override
  Future<void> saveApprovalMode(String? value) async {
    savedApprovalMode = value;
    approvalMode = value;
  }
}

class _DelayedAdditionalWorkspaceStore extends _FakeRuntimeConfigurationStore {
  final savedSnapshots = <List<String>>[];
  final saveCompleters = <Completer<void>>[];

  /// 记录目录快照并延迟写入完成，用于验证保存顺序。
  /// Records directory snapshots and delays completion to verify save ordering.
  @override
  Future<void> saveAdditionalWorkspaces(List<String> workspaces) {
    savedSnapshots.add(List.of(workspaces));
    final completer = Completer<void>();
    saveCompleters.add(completer);
    return completer.future;
  }
}

class _MemoryConversationHistoryStore extends ConversationHistoryStore {
  final snapshots = <String, ConversationHistorySnapshot>{};

  /// 从内存快照表读取指定项目的历史。
  /// Reads a workspace history from the in-memory snapshot map.
  @override
  Future<ConversationHistorySnapshot?> read(String workspace) async {
    return snapshots[workspace];
  }

  /// 将指定项目的历史快照保存到内存。
  /// Saves a workspace history snapshot in memory.
  @override
  Future<void> save({
    required String workspace,
    required ConversationHistorySnapshot snapshot,
  }) async {
    snapshots[workspace] = snapshot;
  }
}

class _BlockingConversationHistoryStore
    extends _MemoryConversationHistoryStore {
  final firstSaveStarted = Completer<void>();
  final allowFirstSave = Completer<void>();
  int saveCalls = 0;

  /// 可选地阻塞第一次保存，以验证控制器的写入串行化。
  /// Optionally blocks the first save to verify controller write serialization.
  @override
  Future<void> save({
    required String workspace,
    required ConversationHistorySnapshot snapshot,
  }) async {
    saveCalls++;
    if (saveCalls == 1) {
      firstSaveStarted.complete();
      await allowFirstSave.future;
    }
    await super.save(workspace: workspace, snapshot: snapshot);
  }
}

class _MemoryLocalSessionThreadStore extends LocalSessionThreadStore {
  final threadsByWorkspace = <String, List<CodexThread>>{};

  /// 从测试内存映射返回指定工作区的本地 session 线程。
  /// Returns local session threads for a workspace from a test memory map.
  @override
  Future<List<CodexThread>> listThreads(String workspace) async {
    return threadsByWorkspace[workspace] ?? const [];
  }
}

class _MemoryCodexPluginStore extends CodexPluginStore {
  final plugins = <CodexPlugin>[];
  final addedMarketplaces = <String>[];
  final marketplaces = <CodexMarketplace>[];
  final installedPluginIds = <String>[];
  final removedPluginIds = <String>[];
  final upgradedMarketplaceNames = <String?>[];
  final removedMarketplaceNames = <String>[];
  final enabledChanges = <String, bool>{};

  /// 从测试内存列表返回已安装与可安装插件。
  /// Returns installed and available plugins from the test memory list.
  @override
  Future<List<CodexPlugin>> listPlugins() async => List.of(plugins);

  /// 记录添加的本地 marketplace，供控制器行为断言。
  /// Records a local marketplace addition for controller behavior assertions.
  @override
  Future<void> addLocalMarketplace(String directory) async {
    addedMarketplaces.add(directory);
  }

  /// 记录本地或远程 marketplace 来源，供控制器行为断言。
  /// Records a local or remote marketplace source for controller behavior assertions.
  @override
  Future<void> addMarketplace(String source) async {
    addedMarketplaces.add(source);
  }

  /// 从测试内存列表返回 marketplace 来源。
  /// Returns marketplace sources from the test memory list.
  @override
  Future<List<CodexMarketplace>> listMarketplaces() async =>
      List.of(marketplaces);

  /// 记录 marketplace 更新请求。
  /// Records a marketplace upgrade request.
  @override
  Future<void> upgradeMarketplace(String? name) async {
    upgradedMarketplaceNames.add(name);
  }

  /// 记录被移除的 marketplace 名称。
  /// Records the name of a removed marketplace.
  @override
  Future<void> removeMarketplace(CodexMarketplace marketplace) async {
    removedMarketplaceNames.add(marketplace.name);
  }

  /// 记录待安装插件，并将其状态改为已安装。
  /// Records a plugin installation and changes its state to installed.
  @override
  Future<void> installPlugin(CodexPlugin plugin) async {
    installedPluginIds.add(plugin.id);
    final index = plugins.indexWhere((value) => value.id == plugin.id);
    if (index >= 0) {
      plugins[index] = CodexPlugin(
        id: plugin.id,
        name: plugin.name,
        marketplaceName: plugin.marketplaceName,
        installed: true,
        enabled: true,
        version: plugin.version,
        installPolicy: plugin.installPolicy,
        authPolicy: plugin.authPolicy,
      );
    }
  }

  /// 记录待卸载插件，并从测试内存列表中移除它。
  /// Records a plugin removal and removes it from the test memory list.
  @override
  Future<void> removePlugin(CodexPlugin plugin) async {
    removedPluginIds.add(plugin.id);
    plugins.removeWhere((value) => value.id == plugin.id);
  }

  /// 记录插件启用状态，并同步测试内存列表。
  /// Records a plugin enabled state and synchronizes the test memory list.
  @override
  Future<void> setPluginEnabled(CodexPlugin plugin, bool enabled) async {
    enabledChanges[plugin.id] = enabled;
    final index = plugins.indexWhere((value) => value.id == plugin.id);
    if (index >= 0) plugins[index] = plugins[index].copyWith(enabled: enabled);
  }
}

class _BlockingCodexPluginStore extends _MemoryCodexPluginStore {
  final installCompleter = Completer<void>();

  /// 保持安装操作未完成，供界面断言进行中状态。
  /// Keeps installation pending so the interface can assert its progress state.
  @override
  Future<void> installPlugin(CodexPlugin plugin) async {
    await installCompleter.future;
    await super.installPlugin(plugin);
  }
}

class _FailingCodexPluginStore extends _MemoryCodexPluginStore {
  /// 模拟 CLI 安装失败并返回可展示的具体原因。
  /// Simulates a CLI installation failure with a displayable reason.
  @override
  Future<void> installPlugin(CodexPlugin plugin) async {
    throw StateError('marketplace 无法访问');
  }
}

class _FailOnSecondInstallCodexPluginStore extends _MemoryCodexPluginStore {
  var installCalls = 0;

  /// 首次安装成功，第二次失败，用于验证待重启提示不会丢失。
  /// Succeeds once, then fails to verify pending restart feedback persists.
  @override
  Future<void> installPlugin(CodexPlugin plugin) async {
    installCalls++;
    if (installCalls == 2) throw StateError('second install failed');
    await super.installPlugin(plugin);
  }
}

class _FakeGitProjectService extends GitProjectService {
  GitProjectStatus status = const GitProjectStatus(isRepository: false);
  String diff = '';
  GitProjectChange? requestedChange;
  int inspectCalls = 0;
  Object? stageError;

  /// 返回预设的只读 Git 项目状态，并记录调用次数。
  /// Returns the preset read-only Git project status and records the call count.
  @override
  Future<GitProjectStatus> inspect(String workspace) async {
    inspectCalls++;
    return status;
  }

  /// 返回预设 Diff，并记录界面请求的文件变更。
  /// Returns the preset diff and records the change requested by the interface.
  @override
  Future<String> readDiff({
    required String workspace,
    required GitProjectChange change,
  }) async {
    requestedChange = change;
    return diff;
  }

  @override
  Future<GitDiffPreview> readDiffPreview({
    required String workspace,
    required GitProjectChange change,
  }) async {
    requestedChange = change;
    return GitDiffPreview(
      content: diff,
      truncated: diff.endsWith(GitProjectService.truncatedDiffMarker),
    );
  }

  @override
  Future<void> stageFile({
    required String workspace,
    required GitProjectChange change,
  }) async {
    if (stageError case final error?) throw error;
  }
}

class _FakeCodexAppServer extends CodexAppServer {
  _FakeCodexAppServer() : super(executable: '/not/a/codex');

  final listRequests = <Completer<List<JsonMap>>>[];
  List<JsonMap> listResponse = <JsonMap>[];
  List<JsonMap> archivedListResponse = <JsonMap>[];
  List<JsonMap> modelListResponse = <JsonMap>[];
  Object? modelListError;
  JsonMap configReadResponse = {
    'config': <String, Object?>{},
    'origins': <String, Object?>{},
  };
  String? configReadDirectory;
  bool queueListRequests = false;
  Object? resumeError;
  JsonMap resumeResult = {
    'thread': {'turns': <JsonMap>[]},
  };
  JsonMap turnPage = {'data': <JsonMap>[]};
  final turnPageCursors = <String?>[];
  JsonMap itemPage = {'data': <JsonMap>[]};
  final itemPageTurnIds = <String>[];
  Object? itemPageError;
  List<JsonMap>? itemPages;
  var itemPageIndex = 0;
  String? resumedThreadId;
  int resumeCalls = 0;
  String? resumedModelProvider;
  String? resumedModel;
  JsonMap? resumedConfig;
  String? startedThreadDirectory;
  List<String>? startedRuntimeWorkspaceRoots;
  String? startedModelProvider;
  String? startedModel;
  JsonMap? startedConfig;
  List<JsonMap> skillListResponse = <JsonMap>[];
  String? startedTurnPrompt;
  String? startedTurnThreadId;
  final List<String> startedTurnThreadIds = [];
  final List<String> startThreadResponseIds = [];
  List<JsonMap> startedTurnAdditionalInput = <JsonMap>[];
  JsonMap? startedTurnCollaborationMode;
  Object? startTurnError;
  String? steeredTurnThreadId;
  String? steeredTurnId;
  String? steeredTurnPrompt;
  List<JsonMap> steeredTurnAdditionalInput = <JsonMap>[];
  String? steerResponseTurnId;
  Object? steerTurnError;
  Completer<String>? steerCompleter;
  String? interruptedThreadId;
  String? interruptedTurnId;
  Completer<void>? interruptCompleter;
  Object? interruptTurnError;
  Object? unarchiveError;
  String? threadGoal;
  String? renamedThreadId;
  String? renamedThreadName;
  String? unarchivedThreadId;
  int unarchiveCalls = 0;
  Completer<void>? unarchiveCompleter;
  final archivedThreadIds = <String>[];
  int archiveCalls = 0;
  Completer<void>? archiveCompleter;
  Object? archiveError;
  final archiveErrorsById = <String, Object>{};
  final deletedThreadIds = <String>[];
  final archiveFailureIds = <String>{};

  /// 始终报告运行中，模拟已连接的 App Server。
  /// Always reports running, simulating a connected App Server.
  @override
  bool get isRunning => true;

  /// 返回预设线程列表，或排队请求以控制刷新竞争测试。
  /// Returns preset threads or queues requests to control refresh-race tests.
  @override
  Future<List<JsonMap>> listThreads({
    required String workingDirectory,
    bool archived = false,
  }) {
    if (archived) return Future.value(archivedListResponse);
    if (!queueListRequests) return Future.value(listResponse);
    final completer = Completer<List<JsonMap>>();
    listRequests.add(completer);
    return completer.future;
  }

  /// 返回预设模型能力列表。
  /// Returns the preset model-capability list.
  @override
  Future<List<JsonMap>> listModels({bool includeHidden = false}) async {
    if (modelListError case final error?) throw error;
    return modelListResponse;
  }

  /// 返回 App Server 已按层级合并的配置，并记录用于解析项目配置的目录。
  /// Returns App Server's merged configuration and records the workspace used to resolve project layers.
  @override
  Future<JsonMap> readConfig({String? workingDirectory}) async {
    configReadDirectory = workingDirectory;
    return configReadResponse;
  }

  /// 记录恢复参数，并返回预设结果或抛出预设异常。
  /// Records resume parameters and returns a preset result or error.
  @override
  Future<JsonMap> resumeThread({
    required String threadId,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    resumeCalls++;
    resumedThreadId = threadId;
    resumedModelProvider = modelProvider;
    resumedModel = model;
    resumedConfig = config;
    final error = resumeError;
    if (error != null) throw error;
    return resumeResult;
  }

  /// 记录新线程参数并返回稳定的测试线程 ID。
  /// Records new-thread parameters and returns a stable test thread ID.
  @override
  Future<String> startThread({
    required String workingDirectory,
    List<String>? runtimeWorkspaceRoots,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    startedThreadDirectory = workingDirectory;
    startedRuntimeWorkspaceRoots = runtimeWorkspaceRoots;
    startedModelProvider = modelProvider;
    startedModel = model;
    startedConfig = config;
    return startThreadResponseIds.isEmpty
        ? 'new-thread'
        : startThreadResponseIds.removeAt(0);
  }

  /// 接受模拟任务启动，不与真实运行时通信。
  /// Accepts a simulated turn start without communicating with a runtime.
  @override
  Future<void> startTurn({
    required String threadId,
    required String prompt,
    required String workingDirectory,
    List<JsonMap> additionalInput = const [],
    JsonMap? collaborationMode,
  }) async {
    startedTurnThreadId = threadId;
    startedTurnThreadIds.add(threadId);
    startedTurnPrompt = prompt;
    startedTurnAdditionalInput = List.of(additionalInput);
    startedTurnCollaborationMode = collaborationMode;
    if (startTurnError case final error?) throw error;
  }

  @override
  Future<String> steerTurn({
    required String threadId,
    required String expectedTurnId,
    required String prompt,
    List<JsonMap> additionalInput = const [],
  }) async {
    steeredTurnThreadId = threadId;
    steeredTurnId = expectedTurnId;
    steeredTurnPrompt = prompt;
    steeredTurnAdditionalInput = List.of(additionalInput);
    if (steerTurnError case final error?) throw error;
    if (steerCompleter case final completer?) return completer.future;
    return steerResponseTurnId ?? expectedTurnId;
  }

  @override
  Future<void> interruptTurn({
    required String threadId,
    required String turnId,
  }) async {
    interruptedThreadId = threadId;
    interruptedTurnId = turnId;
    await interruptCompleter?.future;
    if (interruptTurnError case final error?) throw error;
  }

  @override
  Future<void> setThreadGoal({
    required String threadId,
    required String objective,
  }) async {
    threadGoal = objective;
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    renamedThreadId = threadId;
    renamedThreadName = name;
  }

  @override
  Future<List<JsonMap>> listSkills({
    required String workingDirectory,
    bool forceReload = false,
  }) async => List.of(skillListResponse);

  /// 返回预设 turn 页面并记录使用的游标。
  /// Returns a preset turn page and records the cursor used.
  @override
  Future<JsonMap> listThreadTurns({
    required String threadId,
    String? cursor,
    int limit = 50,
    String sortDirection = 'desc',
  }) async {
    turnPageCursors.add(cursor);
    return turnPage;
  }

  /// 返回预设项目页面、记录 turn，并可模拟读取失败。
  /// Returns preset item pages, records the turn, and can simulate a read failure.
  @override
  Future<JsonMap> listThreadItems({
    required String threadId,
    required String turnId,
    String? cursor,
    int limit = 50,
  }) async {
    itemPageTurnIds.add(turnId);
    final error = itemPageError;
    if (error != null) throw error;
    final pages = itemPages;
    if (pages != null && itemPageIndex < pages.length) {
      return pages[itemPageIndex++];
    }
    return itemPage;
  }

  /// 记录恢复归档请求，并可延迟完成以测试重复提交防护。
  /// Records an unarchive request and can delay completion for duplicate-submit tests.
  @override
  Future<void> unarchiveThread({required String threadId}) async {
    unarchivedThreadId = threadId;
    unarchiveCalls++;
    await unarchiveCompleter?.future;
    if (unarchiveError case final error?) throw error;
    archivedListResponse = <JsonMap>[];
  }

  /// 记录归档请求，并从活跃测试列表中移除相应任务。
  /// Records archive requests and removes corresponding tasks from the active test list.
  @override
  Future<void> archiveThread({required String threadId}) async {
    archiveCalls++;
    await archiveCompleter?.future;
    if (archiveError case final error?) throw error;
    if (archiveErrorsById[threadId] case final error?) throw error;
    if (archiveFailureIds.contains(threadId)) {
      throw StateError('无法归档 $threadId');
    }
    archivedThreadIds.add(threadId);
    listResponse = listResponse
        .where((value) => value['id']?.toString() != threadId)
        .toList(growable: false);
  }

  /// 记录永久删除请求，并从活跃和归档测试列表中移除相应任务。
  /// Records permanent deletion requests and removes matching tasks from both test lists.
  @override
  Future<void> deleteThread({required String threadId}) async {
    deletedThreadIds.add(threadId);
    listResponse = listResponse
        .where((value) => value['id']?.toString() != threadId)
        .toList(growable: false);
    archivedListResponse = archivedListResponse
        .where((value) => value['id']?.toString() != threadId)
        .toList(growable: false);
  }
}

class _ManagedRuntimeFakeServer extends _FakeCodexAppServer {
  bool running = false;
  int startCalls = 0;
  int stopCalls = 0;
  String? runtimeDirectory;

  @override
  bool get isRunning => running;

  /// 返回可用的模拟 CLI 探测结果。
  /// Returns an available fake CLI probe result.
  @override
  Future<CodexRuntimeProbe> probe() async => const CodexRuntimeProbe(
    isAvailable: true,
    executablePath: '/fake/codex',
    version: 'codex fake',
    discovery: '测试运行时',
  );

  /// 记录自动连接使用的主目录。
  /// Records the primary directory used for automatic connection.
  @override
  Future<void> start({required String workingDirectory}) async {
    startCalls++;
    runtimeDirectory = workingDirectory;
    running = true;
  }

  /// 接受模拟初始化握手。
  /// Accepts the fake initialization handshake.
  @override
  Future<void> initialize() async {}

  /// 返回无需登录的模拟账户状态。
  /// Returns a fake account state that does not require login.
  @override
  Future<JsonMap> readAccount() async => {
    'account': null,
    'requiresOpenaiAuth': false,
  };

  /// 记录自动断开操作。
  /// Records an automatic disconnect operation.
  @override
  Future<void> stop() async {
    stopCalls++;
    running = false;
  }
}

class _BlockingRuntimeFakeServer extends _ManagedRuntimeFakeServer {
  final probeCompleter = Completer<CodexRuntimeProbe>();

  /// 延迟 CLI 探测，供测试在连接中销毁控制器。
  /// Delays CLI probing so tests can dispose the controller during connection.
  @override
  Future<CodexRuntimeProbe> probe() => probeCompleter.future;
}

class _DelayedStartRuntimeFakeServer extends _ManagedRuntimeFakeServer {
  final startEntered = Completer<void>();
  final allowStart = Completer<void>();

  @override
  Future<void> start({required String workingDirectory}) async {
    if (!startEntered.isCompleted) startEntered.complete();
    await allowStart.future;
    await super.start(workingDirectory: workingDirectory);
  }
}

/// 创建具有可预测字段的测试线程。
/// Creates a test thread with predictable fields.
CodexThread _thread({
  required String id,
  String? modelProvider,
  String? model,
  String? status,
}) => CodexThread(
  id: id,
  preview: 'preview-$id',
  createdAt: 1,
  updatedAt: 2,
  modelProvider: modelProvider,
  model: model,
  status: status,
);

/// 注册 Codex Desk 的 Widget、控制器与协议回归测试。
/// Registers Codex Desk widget, controller, and protocol regression tests.
final class _MemoryThemePreferencesStore implements CodexThemePreferencesStore {
  final List<CodexThemePreferences> saved = [];

  @override
  Future<CodexThemePreferences> load() async => CodexThemePreferences.defaults;

  @override
  Future<void> save(CodexThemePreferences preferences) async {
    saved.add(preferences);
  }
}

class _ProtocolCaptureCodexAppServer extends CodexAppServer {
  String? requestedMethod;
  JsonMap? requestedParams;
  final notifications = <String>[];

  /// 捕获协议请求并返回稳定响应，不启动真实子进程。
  /// Captures a protocol request and returns a stable response without starting a child process.
  @override
  Future<JsonMap> request(String method, [JsonMap params = const {}]) async {
    requestedMethod = method;
    requestedParams = params;
    if (method == 'turn/steer') {
      return {
        'result': {'turnId': 'turn-1'},
      };
    }
    return {
      'result': {
        'thread': {'id': 'thread-with-roots'},
      },
    };
  }

  /// 捕获初始化完成通知，避免协议测试依赖真实子进程。
  /// Captures initialization notifications without requiring a real child process.
  @override
  void notify(String method, [JsonMap params = const {}]) {
    notifications.add(method);
  }
}

final class _InjectedCodexControllerNotifier extends CodexControllerNotifier {
  _InjectedCodexControllerNotifier(this.controller);

  final CodexController controller;

  @override
  CodexController build() {
    controller.addListener(_publishControllerChange);
    ref.onDispose(() {
      controller.removeListener(_publishControllerChange);
      controller.dispose();
    });
    return controller;
  }

  void _publishControllerChange() => state = controller;
}

void main() {
  late _MemoryConversationHistoryStore historyStore;
  late _FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    historyStore = _MemoryConversationHistoryStore();
    runtimeConfigurationStore = _FakeRuntimeConfigurationStore();
    CodexController.testingConversationHistoryStore = historyStore;
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  testWidgets('shows the Codex Desk shell', (tester) async {
    await tester.pumpWidget(const CodexDeskApp());

    expect(find.text('Codex Desk'), findsOneWidget);
    expect(find.text('新建第一个工作区'), findsOneWidget);
    expect(find.text('等待目录'), findsOneWidget);
    expect(find.byKey(const Key('runtime-start-button')), findsNothing);
    expect(find.byTooltip('停止运行时'), findsNothing);
    expect(find.text('新建任务'), findsOneWidget);
    expect(find.byKey(const Key('sidebar-new-chat-button')), findsOneWidget);
    expect(
      find.byKey(const Key('sidebar-pull-requests-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('sidebar-scheduled-tasks-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sidebar-plugins-button')), findsOneWidget);
    expect(tester.widget<Text>(find.text('新对话')).style?.fontSize, 14);
  });

  test('persists and cancels a scheduled prompt', () async {
    final store = _FakeRuntimeConfigurationStore();
    final controller = CodexController(runtimeConfigurationStore: store)
      ..workspacePath = '/workspace';

    final scheduled = await controller.schedulePrompt(
      prompt: '检查测试结果',
      runAt: DateTime.now().add(const Duration(hours: 1)),
    );

    expect(scheduled, isTrue);
    expect(controller.scheduledTasks, hasLength(1));
    expect(store.savedScheduledTasks, hasLength(1));
    await controller.cancelScheduledTask(controller.scheduledTasks.single.id);
    expect(controller.scheduledTasks, isEmpty);
    expect(store.savedScheduledTasks, isEmpty);
    controller.dispose();
  });

  test(
    'does not dispatch a scheduled prompt cancelled during project switch',
    () async {
      final first = await Directory.systemTemp.createTemp(
        'codex-desk-schedule-current-',
      );
      final second = await Directory.systemTemp.createTemp(
        'codex-desk-schedule-target-',
      );
      addTearDown(() => first.delete(recursive: true));
      addTearDown(() => second.delete(recursive: true));
      final server = _DelayedStartRuntimeFakeServer()..running = true;
      final controller = CodexController(server: server);
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = first.path
        ..status = RuntimeStatus.ready;

      expect(
        await controller.schedulePrompt(
          prompt: '这条任务已经取消，不能发送',
          runAt: DateTime.now().add(const Duration(milliseconds: 100)),
        ),
        isTrue,
      );
      final taskId = controller.scheduledTasks.single.id;
      // Simulate the user moving to another idle project before the timer fires.
      // The dispatch now has to await a runtime switch back to the task project.
      controller.workspacePath = second.path;
      await server.startEntered.future;
      await controller.cancelScheduledTask(taskId);
      server.allowStart.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.scheduledTasks, isEmpty);
      expect(server.startedTurnPrompt, isNull);
      controller.dispose();
    },
  );

  testWidgets('opens the three project-library workspaces from the sidebar', (
    tester,
  ) async {
    final controller =
        CodexController(
            server: CodexAppServer(),
            pluginStore: _MemoryCodexPluginStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-scheduled-tasks-button')));
    await tester.pump();
    expect(find.byKey(const Key('scheduled-tasks-page')), findsOneWidget);
    expect(find.text('已安排的任务'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    expect(find.byKey(const Key('plugins-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-pull-requests-button')));
    await tester.pump();
    expect(find.text('Pull Request'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switches plugin library tabs and starts plugin or skill flows', (
    tester,
  ) async {
    final server = _FakeCodexAppServer()
      ..skillListResponse = const [
        {
          'name': 'skill-creator',
          'path': '/skills/skill-creator/SKILL.md',
          'description': 'Create reusable skills',
          'enabled': true,
          'scope': 'system',
          'interface': {
            'displayName': 'Skill Creator',
            'shortDescription': 'Create a reusable Codex skill',
          },
        },
      ];
    final controller =
        CodexController(server: server, pluginStore: _MemoryCodexPluginStore())
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-skills-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skills-page')), findsOneWidget);
    expect(find.text('Skill Creator'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plugins-tab')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建插件'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .text,
      r'$plugin-creator help me create a plugin',
    );

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('录制技能'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('composer-record-skill-chip')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens the marketplace source form from plugin add menu', (
    tester,
  ) async {
    final controller =
        CodexController(
            server: _FakeCodexAppServer(),
            pluginStore: _MemoryCodexPluginStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plugins-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加插件市场'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-marketplace-dialog')), findsOneWidget);
    expect(find.byKey(const Key('marketplace-source-field')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gives the project and workbench columns independent top bars', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final projectTopBar = find.byKey(const Key('workspace-column-topbar'));
    final workbenchTopBar = find.byKey(const Key('workbench-column-topbar'));
    final sidebar = find.byKey(const Key('sidebar-pane'));

    expect(projectTopBar, findsOneWidget);
    expect(workbenchTopBar, findsOneWidget);
    expect(tester.getTopLeft(projectTopBar).dx, lessThan(250));
    expect(
      tester.getTopLeft(workbenchTopBar).dx,
      greaterThan(tester.getTopLeft(projectTopBar).dx),
    );
    expect(
      tester.getTopLeft(sidebar).dy,
      greaterThan(tester.getBottomLeft(projectTopBar).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('workbench-task-title'))).dy,
      lessThan(tester.getBottomLeft(workbenchTopBar).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('composer-panel'))).dy,
      greaterThan(tester.getBottomLeft(workbenchTopBar).dy),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows unknown file stats when a Diff has no countable lines', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'assets/logo.png',
                'kind': 'modified',
                'diff': 'diff --git a/assets/logo.png b/assets/logo.png',
              },
            ],
          },
        },
      ),
    );
    await tester.pump();

    final pill = find.byKey(const Key('composer-file-change-pill'));
    expect(
      find.descendant(of: pill, matching: find.text('+?')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pill, matching: find.text('-?')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('edits the current task name from the workbench top bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'active-task'
      ..threads = [
        const CodexThread(
          id: 'active-task',
          name: '初始任务名称',
          preview: '任务预览',
          createdAt: 1,
          updatedAt: 1,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final topBar = find.byKey(const Key('workbench-column-topbar'));
    expect(
      find.descendant(of: topBar, matching: find.text('初始任务名称')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topBar, matching: find.text('Codex 配置 / App Server')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topBar, matching: find.text('workspace-write')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: topBar,
        matching: find.byKey(const Key('workbench-file-changes-button')),
      ),
      findsOneWidget,
    );
    expect(find.text('任务控制台'), findsNothing);

    await tester.tap(find.byKey(const Key('workbench-task-title')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('workbench-task-title-editor')),
      '整理桌面工作台布局',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(server.renamedThreadId, 'active-task');
    expect(server.renamedThreadName, '整理桌面工作台布局');
    expect(
      find.descendant(of: topBar, matching: find.text('整理桌面工作台布局')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'provider updates keep the conversation timeline at the latest item',
    (tester) async {
      final controller = CodexController(
        server: _FakeCodexAppServer(),
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      final initialEntries = List<TimelineEntry>.generate(
        30,
        (index) => TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '历史消息 $index\n${'内容 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 0, index),
        ),
      );
      controller.replaceTimelineEntriesForTesting(initialEntries);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            codexControllerProvider.overrideWith(
              () => _InjectedCodexControllerNotifier(controller),
            ),
          ],
          child: const MaterialApp(home: CodexWorkspace()),
        ),
      );
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
      final timeline = tester.widget<ListView>(find.byType(ListView));
      expect(timeline.controller!.offset, 0);
      expect(timeline.controller!.position.maxScrollExtent, greaterThan(0));

      controller.replaceTimelineEntriesForTesting([
        ...initialEntries,
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '最新消息\n${'新内容 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 1),
        ),
      ]);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(timeline.controller!.position.extentAfter, lessThan(32));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('switches the UI Kit display mode from the theme menu', (
    tester,
  ) async {
    await tester.pumpWidget(const CodexDeskApp());

    await tester.tap(find.byTooltip('主题：深色 · 午夜'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-mode-light')));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Codex Desk'))).brightness,
      Brightness.light,
    );
    final picker = tester.widget<Ink>(
      find.byKey(const Key('workspace-picker-surface')),
    );
    expect(
      (picker.decoration! as BoxDecoration).color,
      YeknomPalette.of(tester.element(find.text('新建第一个工作区'))).raised,
    );
  });

  testWidgets('shows saved workspaces as a switchable sidebar list', (
    tester,
  ) async {
    late Directory root;
    late String firstPath;
    late String secondPath;
    late CodexController controller;
    late _FakeRuntimeConfigurationStore runtimeStore;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'codex-desk-sidebar-workspaces-',
      );
      final first = await Directory(
        '${root.path}/first-project',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second-project',
      ).create(recursive: true);
      final additional = await Directory(
        '${root.path}/shared',
      ).create(recursive: true);
      firstPath = await first.resolveSymbolicLinks();
      secondPath = await second.resolveSymbolicLinks();
      runtimeStore = _FakeRuntimeConfigurationStore()
        ..workspace = second.path
        ..workspaces = [
          WorkspaceConfiguration(
            primaryPath: first.path,
            additionalPaths: [additional.path],
          ),
          WorkspaceConfiguration(primaryPath: second.path),
        ];
      controller = CodexController(
        server: _ManagedRuntimeFakeServer(),
        runtimeConfigurationStore: runtimeStore,
      );
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.ready;
      controller.threads = [
        _thread(id: 'nested-task', status: 'idle'),
        _thread(id: 'delayed-completion-task'),
        _thread(id: 'failed-task', status: 'systemError'),
      ];
      historyStore.snapshots[firstPath] = ConversationHistorySnapshot(
        // 缓存中可能保留了已在其他项目恢复的同一线程 ID；它不能继承
        // 当前项目的选中态或运行中状态。
        threads: [
          const CodexThread(
            id: 'nested-task',
            preview: 'preview-cached-first-task',
            createdAt: 1,
            updatedAt: 2,
          ),
        ],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
      );
      await controller.refreshInactiveWorkspaceTaskLists();
    });
    addTearDown(() => root.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final firstTile = find.byKey(ValueKey('sidebar-workspace-$firstPath'));
    final secondTile = find.byKey(ValueKey('sidebar-workspace-$secondPath'));
    expect(firstTile, findsOneWidget);
    expect(secondTile, findsOneWidget);
    expect(find.text('first-project'), findsOneWidget);
    expect(find.text('second-project'), findsOneWidget);
    expect(find.text(firstPath), findsNothing);
    expect(find.byTooltip(firstPath), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    final nestedTask = find.text('preview-nested-task');
    expect(nestedTask, findsOneWidget);
    expect(
      tester.getTopLeft(nestedTask).dy,
      greaterThan(tester.getBottomLeft(secondTile).dy),
    );
    expect(
      tester.getTopLeft(nestedTask).dx,
      greaterThan(tester.getTopLeft(secondTile).dx),
    );
    expect(
      find.byKey(const Key('sidebar-completed-task-indicator')),
      findsOneWidget,
    );
    await tester.ensureVisible(nestedTask);
    await tester.tap(nestedTask);
    await tester.pump();
    expect(
      find.byKey(const Key('sidebar-completed-task-indicator')),
      findsNothing,
    );
    // The completion status can arrive after a task has already been opened.
    // That delayed refresh must not revive an old completion reminder.
    final delayedTask = find.text('preview-delayed-completion-task');
    await tester.ensureVisible(delayedTask);
    await tester.tap(delayedTask);
    await tester.pump();
    controller.threads = [
      _thread(id: 'nested-task', status: 'idle'),
      _thread(id: 'delayed-completion-task', status: 'idle'),
      _thread(id: 'failed-task', status: 'systemError'),
    ];
    controller.notifyListeners();
    await tester.pump();
    expect(
      find.byKey(const Key('sidebar-completed-task-indicator')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(firstTile).dy,
      lessThan(tester.getTopLeft(secondTile).dy),
    );
    expect(
      tester
          .widget<InkWell>(
            find
                .descendant(of: firstTile, matching: find.byType(InkWell))
                .first,
          )
          .onTap,
      isNotNull,
    );
    expect(
      tester
          .widget<InkWell>(
            find
                .descendant(of: secondTile, matching: find.byType(InkWell))
                .first,
          )
          .onTap,
      isNull,
    );
    await tester.ensureVisible(firstTile);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await tester.ensureVisible(firstTile);
    await mouse.moveTo(tester.getCenter(firstTile));
    await tester.pump();
    final moreButton = find.byKey(
      ValueKey('sidebar-workspace-more-$firstPath'),
    );
    final newTaskButton = find.byKey(
      ValueKey('sidebar-workspace-edit-$firstPath'),
    );
    expect(moreButton, findsOneWidget);
    expect(newTaskButton, findsOneWidget);
    // 项目详情卡片只会在持续悬停后显示。
    expect(find.text('1 个任务'), findsNothing);
    expect(find.text('编辑项目'), findsNothing);
    await tester.pump(codexHoverPopupDelay - const Duration(milliseconds: 1));
    expect(find.text('1 个任务'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('1 个任务'), findsOneWidget);
    expect(find.text('编辑项目'), findsOneWidget);
    // A project can receive new tasks after its count was first shown. Opening
    // its details again must reload the local cache instead of retaining 1.
    await tester.ensureVisible(secondTile);
    await mouse.moveTo(tester.getCenter(secondTile));
    await tester.pump(const Duration(milliseconds: 180));
    historyStore.snapshots[firstPath] = ConversationHistorySnapshot(
      threads: [
        const CodexThread(
          id: 'nested-task',
          preview: 'preview-cached-first-task',
          createdAt: 1,
          updatedAt: 2,
        ),
        const CodexThread(
          id: 'new-cached-first-task',
          preview: 'preview-new-cached-first-task',
          createdAt: 3,
          updatedAt: 4,
        ),
      ],
      archivedThreads: const [],
      entries: const [],
      fileChanges: const [],
    );
    await tester.ensureVisible(firstTile);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(firstTile));
    await tester.pump(codexHoverPopupDelay);
    await tester.pump();
    expect(find.text('2 个任务'), findsOneWidget);
    await tester.tap(find.byTooltip('置顶项目'));
    await tester.pumpAndSettle();
    expect(controller.isWorkspacePinned(firstPath), isTrue);
    expect(runtimeStore.savedPinnedWorkspaces, {firstPath});
    expect(find.byTooltip('取消置顶项目'), findsOneWidget);
    await tester.tap(moreButton);
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('创建永久工作树'), findsOneWidget);
    expect(find.text('归档聊天'), findsOneWidget);
    expect(find.text('移除项目'), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('workspace-directories-dialog')),
      findsOneWidget,
    );
    final projectNameField = tester.widget<TextField>(
      find.byKey(const Key('workspace-project-name-field')),
    );
    final projectNameDecoration = projectNameField.decoration!;
    expect(projectNameDecoration.filled, isFalse);
    expect(projectNameDecoration.border, InputBorder.none);
    expect(projectNameDecoration.enabledBorder, InputBorder.none);
    expect(projectNameDecoration.focusedBorder, InputBorder.none);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    controller
      ..activeThreadId = 'nested-task'
      ..status = RuntimeStatus.ready
      ..notifyListeners();
    await tester.pump();
    await mouse.moveTo(tester.getCenter(firstTile));
    await tester.pump();
    await tester.tap(newTaskButton);
    expect(controller.activeThreadId, isNull);
    controller
      ..activeThreadId = 'nested-task'
      ..status = RuntimeStatus.running
      ..notifyListeners();
    await tester.pump();
    expect(
      find.byKey(const Key('sidebar-running-task-indicator')),
      findsOneWidget,
    );
    final runningTaskIndicator = tester.widget<SizedBox>(
      find.byKey(const Key('sidebar-running-task-indicator')),
    );
    expect(runningTaskIndicator.width, 12);
    expect(runningTaskIndicator.height, 12);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.descendant(
              of: find.byKey(const Key('sidebar-running-task-indicator')),
              matching: find.byType(CircularProgressIndicator),
            ),
          )
          .strokeWidth,
      1.5,
    );
    expect(tester.widget<IconButton>(newTaskButton).onPressed, isNotNull);
    expect(
      tester
          .widget<InkWell>(
            find.ancestor(
              of: find.descendant(
                of: find.byKey(const Key('sidebar-pane')),
                matching: find.text('preview-nested-task'),
              ),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNotNull,
    );
    expect(
      find.byKey(const Key('sidebar-create-workspace-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('sidebar-manage-workspaces-button')),
      findsOneWidget,
    );
    // 启动后，未选中的项目也会从本地缓存读取任务并保持展开；
    // 只有点击该项目自己的按钮才会收起。
    final cachedFirstTask = find.text('preview-cached-first-task');
    expect(cachedFirstTask, findsOneWidget);
    final firstToggle = find.byKey(
      ValueKey('sidebar-workspace-toggle-$firstPath'),
    );
    await tester.tap(firstToggle);
    await tester.pump();
    expect(cachedFirstTask, findsNothing);
    await tester.tap(firstToggle);
    await tester.pump();
    expect(cachedFirstTask, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('creates a project from a dragged source folder', (tester) async {
    late Directory root;
    late Directory source;
    late CodexController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'codex-desk-create-project-',
      );
      source = await Directory('${root.path}/project-source').create();
      controller = CodexController(server: _ManagedRuntimeFakeServer());
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.stopped;
    });
    addTearDown(() => root.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('sidebar-create-workspace-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create-workspace-dialog')), findsOneWidget);
    expect(
      find.byKey(const Key('create-workspace-dialog-title')),
      findsOneWidget,
    );
    expect(find.text('项目名称'), findsOneWidget);
    expect(find.text('添加 Codex 可读取和编辑的文件夹'), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const Key('create-workspace-folder-picker')),
          )
          .onTap,
      isNotNull,
    );

    var dropTarget = tester.widget<DropTarget>(
      find.byKey(const Key('create-workspace-folder-drop-target')),
    );
    dropTarget.onDragEntered?.call(
      DropEventDetails(
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pump();
    expect(find.text('松开即可添加文件夹'), findsOneWidget);

    dropTarget = tester.widget<DropTarget>(
      find.byKey(const Key('create-workspace-folder-drop-target')),
    );
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemDirectory(source.path, const [])],
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('project-source'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel-create-workspace')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create-workspace-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows Codex configuration without provider input fields', (
    tester,
  ) async {
    final server = _FakeCodexAppServer()
      ..configReadResponse = {
        'config': {'model': 'gpt-5.6-sol', 'model_provider': 'company-relay'},
        'origins': {
          'model': {
            'name': {'type': 'project', 'dotCodexFolder': '/workspace/.codex'},
            'version': '1',
          },
          'model_provider': {
            'name': {'type': 'user', 'file': '/Users/test/.codex/config.toml'},
            'version': '1',
          },
        },
      };
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('codex-configuration-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('codex-configuration-dialog')), findsOneWidget);
    expect(find.byKey(const Key('codex-configuration-path')), findsOneWidget);
    expect(find.text('已从 Codex 运行时读取'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('codex-configuration-dialog')),
        matching: find.text('gpt-5.6-sol'),
      ),
      findsOneWidget,
    );
    expect(find.text('company-relay'), findsWidgets);
    expect(find.text('来源：/workspace/.codex/config.toml'), findsOneWidget);
    expect(find.text('来源：/Users/test/.codex/config.toml'), findsOneWidget);
    expect(server.configReadDirectory, '/workspace');
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('模型名称'), findsNothing);
    expect(find.text('中转站 API Key'), findsNothing);
    expect(find.textContaining('本应用不再单独收集或保存这些字段'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switches the new-task model and updates the reasoning menu', (
    tester,
  ) async {
    final server = _FakeCodexAppServer()
      ..modelListResponse = [
        {
          'id': 'deep-model',
          'model': 'deep-model',
          'displayName': 'deep-model',
          'isDefault': true,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'high'},
          ],
        },
        {
          'id': 'fast-model',
          'model': 'fast-model',
          'displayName': 'fast-model',
          'isDefault': false,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'low'},
          ],
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    await controller.refreshReasoningEffortCapabilitiesForTesting();
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('composer-model-controls')), findsOneWidget);
    final composerField = tester.widget<TextField>(
      find.byKey(const Key('composer-field')),
    );
    final composerDecoration = composerField.decoration!;
    expect(composerDecoration.border, InputBorder.none);
    expect(composerDecoration.enabledBorder, InputBorder.none);
    expect(composerDecoration.focusedBorder, InputBorder.none);
    final modelControls = tester.widget<Container>(
      find.byKey(const Key('composer-model-controls')),
    );
    expect((modelControls.decoration! as BoxDecoration).border, isNull);
    await tester.tap(find.byKey(const Key('model-selector')));
    await tester.pumpAndSettle();
    final fastModelItem = find.byKey(const Key('model-option-fast-model'));
    await tester.tapAt(tester.getTopLeft(fastModelItem) + const Offset(12, 12));
    await tester.pumpAndSettle();

    expect(controller.selectedModelId, 'fast-model');
    expect(controller.reasoningEffortOptions, [
      ReasoningEffort.defaultValue,
      ReasoningEffort.low,
    ]);

    await tester.tap(find.byKey(const Key('reasoning-effort-selector')));
    await tester.pumpAndSettle();
    expect(find.text('低'), findsOneWidget);
    expect(find.text('新任务推理强度：低'), findsNothing);
    expect(find.text('高'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('persists display mode and color preset selections', (
    tester,
  ) async {
    final store = _MemoryThemePreferencesStore();
    await tester.pumpWidget(CodexDeskApp(themePreferencesStore: store));

    await tester.tap(find.byTooltip('主题：深色 · 午夜'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-mode-light')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('主题：浅色 · 午夜'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-preset-obsidian')));
    await tester.pumpAndSettle();

    expect(
      store.saved.last,
      const CodexThemePreferences(
        mode: ThemeMode.light,
        preset: YeknomColorPreset.obsidian,
      ),
    );
  });

  testWidgets('sends a composer message when Enter is pressed', (tester) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      '用 Enter 发送',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      controller.entries.map((entry) => entry.detail),
      contains('用 Enter 发送'),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not send a composing IME value when Enter is pressed', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('composer-field')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'nihao',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .value
          .composing,
      const TextRange(start: 0, end: 5),
    );
    final entryCount = controller.entries.length;

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.entries, hasLength(entryCount));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .text,
      'nihao',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'does not send the Enter that has just confirmed an IME candidate',
    (tester) async {
      final controller = CodexController(server: _FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      await tester.tap(find.byKey(const Key('composer-field')));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'nihao',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pump();
      final entryCount = controller.entries.length;

      // Some macOS IMEs clear `composing` before dispatching the same Enter
      // that confirms the selected candidate.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你好',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(controller.entries, hasLength(entryCount));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('composer-field')))
            .controller!
            .text,
        '你好',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('sends after an IME composition was already confirmed', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('composer-field')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'nihao',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你好',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final entryCount = controller.entries.length;

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.entries, hasLength(entryCount + 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uses compact text and a circular send button in the composer', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final sendButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '发送任务',
      ),
    );
    expect(
      sendButton.style?.shape?.resolve(const <WidgetState>{}),
      isA<CircleBorder>(),
    );
    expect(
      sendButton.style?.fixedSize?.resolve(const <WidgetState>{}),
      const Size.square(36),
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('composer-field'))).style,
      isA<TextStyle>().having((style) => style.fontSize, 'fontSize', 14),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uses a circular stop button while a task is running', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final stopButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '停止当前任务',
      ),
    );
    expect(
      stopButton.style?.shape?.resolve(const <WidgetState>{}),
      isA<CircleBorder>(),
    );
    expect(
      stopButton.style?.fixedSize?.resolve(const <WidgetState>{}),
      const Size.square(36),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('floats file change stats without moving the composer', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final composerField = find.byKey(const Key('composer-field'));
    final composerFieldTopBefore = tester.getTopLeft(composerField).dy;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'lib/main.dart',
                'kind': 'modified',
                'diff': '@@ -1 +1 @@\n-old\n+new',
              },
            ],
          },
        },
      ),
    );
    await tester.pump();

    final pill = find.byKey(const Key('composer-file-change-pill'));
    final overlay = find.byKey(const Key('composer-file-change-overlay'));
    expect(pill, findsOneWidget);
    expect(overlay, findsOneWidget);
    expect(
      tester.getTopLeft(composerField).dy,
      moreOrLessEquals(composerFieldTopBefore),
    );
    expect(
      tester.getTopLeft(pill).dy,
      lessThan(tester.getTopLeft(composerField).dy),
    );
    expect(
      find.descendant(of: pill, matching: find.text('1 个文件已更改')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pill, matching: find.text('+1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pill, matching: find.text('-1')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  test('adjusts the active turn direction through the App Server', () async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    final sent = await controller.steerCurrentTurn(
      '改成灰色',
      additionalInput: const [
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ],
    );

    expect(sent, isTrue);
    expect(server.steeredTurnThreadId, 'thread-1');
    expect(server.steeredTurnId, 'turn-1');
    expect(server.steeredTurnPrompt, '改成灰色');
    expect(server.steeredTurnAdditionalInput, [
      {'type': 'localImage', 'path': '/tmp/steer.png'},
    ]);
    expect(controller.entries.any((entry) => entry.detail == '改成灰色'), isTrue);
    controller.dispose();
  });

  test('retains the turn id returned by steering', () async {
    final server = _FakeCodexAppServer()..steerResponseTurnId = 'turn-2';
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    expect(await controller.steerCurrentTurn('继续'), isTrue);
    expect(controller.activeTurnId, 'turn-2');
    controller.dispose();
  });

  test(
    'does not write an in-flight direction into a newly opened task',
    () async {
      final steerCompleter = Completer<String>();
      final server = _FakeCodexAppServer()..steerCompleter = steerCompleter;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '旧任务方向', prompt: '旧任务方向'),
      );

      final send = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);
      expect(server.steeredTurnPrompt, '旧任务方向');

      controller.createThread();
      steerCompleter.complete('turn-1');

      expect(await send, isTrue);
      expect(controller.activeThreadId, isNull);
      expect(controller.pendingTurnSteer, isNull);
      expect(
        controller.entries.map((entry) => entry.detail),
        isNot(contains('旧任务方向')),
      );
      controller.dispose();
    },
  );

  test(
    'does not release a newer direction send when an older send finishes',
    () async {
      final firstCompleter = Completer<String>();
      final secondCompleter = Completer<String>();
      final server = _FakeCodexAppServer()..steerCompleter = firstCompleter;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '旧任务方向', prompt: '旧任务方向'),
      );
      final firstSend = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);

      controller.createThread();
      server.steerCompleter = secondCompleter;
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-2'
        ..activeTurnId = 'turn-2';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '新任务方向', prompt: '新任务方向'),
      );
      final secondSend = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);

      firstCompleter.complete('turn-1');
      expect(await firstSend, isTrue);
      expect(controller.pendingTurnSteer?.prompt, '新任务方向');
      expect(controller.pendingTurnSteerSending, isTrue);
      expect(
        controller.entries.map((entry) => entry.detail),
        isNot(contains('旧任务方向')),
      );

      secondCompleter.complete('turn-2');
      expect(await secondSend, isTrue);
      expect(controller.pendingTurnSteer, isNull);
      expect(controller.pendingTurnSteerSending, isFalse);
      expect(
        controller.entries.map((entry) => entry.detail),
        contains('新任务方向'),
      );
      controller.dispose();
    },
  );

  test(
    'does not write a stale direction failure into a newly opened task',
    () async {
      final steerCompleter = Completer<String>();
      final server = _FakeCodexAppServer()..steerCompleter = steerCompleter;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '旧任务方向', prompt: '旧任务方向'),
      );

      final send = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);
      controller.createThread();
      steerCompleter.completeError(StateError('stale failure'));

      expect(await send, isFalse);
      expect(controller.activeThreadId, isNull);
      expect(controller.lastError, isNull);
      expect(
        controller.entries.map((entry) => entry.title),
        isNot(contains('调整方向失败')),
      );
      controller.dispose();
    },
  );

  testWidgets(
    'keeps a queued direction outside persisted entries and sends directly',
    (tester) async {
      final server = _FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '应该是我图里的样子', prompt: '应该是我图里的样子'),
      );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump();

      final pendingMessage = find.byKey(const Key('pending-turn-steer'));
      final adjustDirection = find.byKey(const Key('adjust-direction-button'));
      final composerPanel = find.byKey(const Key('composer-panel'));
      expect(pendingMessage, findsOneWidget);
      expect(adjustDirection, findsOneWidget);
      expect(find.byKey(const Key('discard-direction-button')), findsOneWidget);
      expect(
        find.descendant(of: composerPanel, matching: pendingMessage),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(pendingMessage).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('composer-field'))).dy),
      );
      expect(
        tester.getCenter(adjustDirection).dx,
        greaterThan(tester.getCenter(pendingMessage).dx),
      );
      expect(find.byKey(const Key('adjust-direction-dialog')), findsNothing);
      await tester.tap(adjustDirection);
      await tester.pump();
      expect(server.steeredTurnPrompt, '应该是我图里的样子');
      expect(controller.pendingTurnSteer, isNull);
      expect(find.byKey(const Key('adjust-direction-dialog')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('does not queue an empty direction while a task is running', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.pendingTurnSteer, isNull);
    expect(find.byKey(const Key('pending-turn-steer')), findsNothing);
    expect(tester.widget<TextField>(field).enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('discards a queued direction from the composer header', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.queueTurnSteer(
      const PendingTurnSteer(displayText: '不要发送这条', prompt: '不要发送这条'),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('discard-direction-button')));
    await tester.pump();

    expect(controller.pendingTurnSteer, isNull);
    expect(find.byKey(const Key('pending-turn-steer')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps the composer editable and accepts attachments while steering an active turn',
    (tester) async {
      const channel = MethodChannel('codex_desk/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => [
          {'path': '/tmp/steer.png', 'isDirectory': false},
        ],
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final server = _FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final field = find.byKey(const Key('composer-field'));
      expect(tester.widget<TextField>(field).enabled, isTrue);
      expect(
        tester
            .widget<PopupMenuButton<dynamic>>(
              find.byKey(const Key('composer-add-button')),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(field);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      // The live thinking indicator deliberately animates while a turn is
      // active, so settling is neither expected nor necessary here.
      await tester.pump();
      expect(
        find.byKey(const Key('composer-attachment-/tmp/steer.png')),
        findsOneWidget,
      );
      await tester.enterText(field, '请改成灰色');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(server.steeredTurnPrompt, isNull);
      expect(controller.pendingTurnSteer?.displayText, '请改成灰色');
      expect(find.byKey(const Key('pending-turn-steer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('adjust-direction-button')));
      await tester.pump();
      expect(server.steeredTurnPrompt, '请改成灰色');
      expect(server.steeredTurnAdditionalInput, [
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ]);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('shows goals, plan mode, and skills from the composer menu', (
    tester,
  ) async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..selectedModelId = 'gpt-test'
      ..modelOptions = const [
        CodexModelOption(
          id: 'gpt-test',
          displayName: 'GPT Test',
          description: '',
          isDefault: true,
        ),
      ]
      ..skills = const [
        CodexSkill(
          name: 'skill-creator',
          path: '/skills/skill-creator/SKILL.md',
          description: 'Create reusable skills',
          enabled: true,
          scope: 'system',
          displayName: 'Skill Creator',
        ),
        CodexSkill(
          name: 'documents',
          path: '/skills/documents/SKILL.md',
          description: 'Create and edit documents',
          enabled: true,
          scope: 'system',
          displayName: 'Documents',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    expect(find.text('文件和文件夹'), findsOneWidget);
    expect(find.text('附加 workspace'), findsOneWidget);
    expect(find.text('插件'), findsAtLeastNWidgets(1));
    expect(find.text('Documents'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-goal-menu-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer-goal-field')),
      '完成附件菜单',
    );
    await tester.tap(find.byKey(const Key('save-composer-goal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-goal-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-plan-mode-menu-item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-plan-mode-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-skill-documents')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-skill-chip-documents')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-skill-menu-item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-record-skill-chip')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('highlights the composer and deduplicates dropped files', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    var dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragEntered?.call(
      DropEventDetails(
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('composer-drop-overlay')), findsOneWidget);
    expect(find.text('松开即可添加文件'), findsOneWidget);

    dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [
          DropItemFile('/tmp/design.png'),
          DropItemFile('/tmp/design.png'),
          DropItemDirectory('/tmp/reference-folder', const []),
        ],
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('composer-drop-overlay')), findsNothing);
    expect(
      find.byKey(const Key('composer-attachment-/tmp/design.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-attachment-/tmp/reference-folder')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pastes copied files and folders as composer attachments', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readFileItems');
      return [
        {'path': '/tmp/copied.png', 'isDirectory': false},
        {'path': '/tmp/copied-folder', 'isDirectory': true},
        {'path': '/tmp/copied.png', 'isDirectory': false},
        {'path': '/tmp/trailing-space ', 'isDirectory': false},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('composer-field')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-attachment-/tmp/copied.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-attachment-/tmp/copied-folder')),
      findsOneWidget,
    );
    expect(find.text('copied.png'), findsOneWidget);
    expect(find.text('copied-folder'), findsOneWidget);
    expect(
      find.byKey(const Key('composer-attachment-/tmp/trailing-space ')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('retains pasted screenshots for the timeline', (tester) async {
    const channel = MethodChannel('codex_desk/clipboard');
    const imagePath = '/tmp/CodexDeskClipboard/clipboard-image-42.png';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var deleteCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readFileItems':
          return [
            {'path': imagePath, 'isDirectory': false, 'isTemporary': true},
          ];
        case 'deleteTemporaryItem':
          expect(call.arguments, imagePath);
          deleteCalls++;
          return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'new-thread'},
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('composer-field')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    final screenshotChip = find.byKey(
      const Key('composer-attachment-$imagePath'),
    );
    expect(screenshotChip, findsOneWidget);
    expect(
      find.descendant(
        of: screenshotChip,
        matching: find.byKey(const Key('composer-image-thumbnail')),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('composer-image-thumbnail')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-image-preview-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('composer-image-preview')), findsOneWidget);
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '关闭预览',
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-image-preview-dialog')),
      findsNothing,
    );
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(server.startedTurnAdditionalInput, [
      {'type': 'localImage', 'path': imagePath},
    ]);
    expect(deleteCalls, 0);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(deleteCalls, 0);
    expect(
      find.byKey(const ValueKey('timeline-image-$imagePath')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(deleteCalls, 1);
  });

  testWidgets('falls back to normal text paste when no file is copied', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': '粘贴文本'};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.enterText(find.byKey(const Key('composer-field')), '已有内容：');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(find.text('已有内容：粘贴文本'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sends image-suffixed directories as path context', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return [
        {'path': '/tmp/reference.png', 'isDirectory': true},
        {'path': '/tmp/design.png', 'isDirectory': false},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'new-thread'},
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.enterText(find.byKey(const Key('composer-field')), '检查附件');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.canSend, isTrue);
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(server.startedTurnPrompt, contains('附加路径：/tmp/reference.png'));
    expect(server.startedTurnAdditionalInput, [
      {'type': 'localImage', 'path': '/tmp/design.png'},
    ]);
    expect(
      find.byKey(const Key('composer-attachment-/tmp/reference.png')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps composer text and attachments when task start fails', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => [
        {'path': '/tmp/retry.txt', 'isDirectory': false},
      ],
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = CodexController(
      server: _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'new-thread'},
        ]
        ..startTurnError = StateError('turn rejected'),
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.enterText(find.byKey(const Key('composer-field')), '保留这个输入');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.canSend, isTrue);
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final field = tester.widget<TextField>(
      find.byKey(const Key('composer-field')),
    );
    expect(field.controller?.text, '保留这个输入');
    expect(
      find.byKey(const Key('composer-attachment-/tmp/retry.txt')),
      findsOneWidget,
    );
    expect(controller.lastError, contains('turn rejected'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('releases dropped security scope after the turn completes', (
    tester,
  ) async {
    const dropChannel = MethodChannel('desktop_drop');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var startCalls = 0;
    var stopCalls = 0;
    messenger.setMockMethodCallHandler(dropChannel, (call) async {
      switch (call.method) {
        case 'startAccessingSecurityScopedResource':
          startCalls++;
          return true;
        case 'stopAccessingSecurityScopedResource':
          stopCalls++;
          return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(dropChannel, null));
    final controller = CodexController(
      server: _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'new-thread'},
        ],
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [
          DropItemFile(
            '/tmp/scoped.txt',
            extraAppleBookmark: Uint8List.fromList([1, 2, 3]),
          ),
        ],
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pumpAndSettle();
    expect(startCalls, 1);

    expect(controller.canSend, isTrue);
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(stopCalls, 0);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(stopCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  test(
    'sends goals, plan mode, and structured skill input to App Server',
    () async {
      final server = _FakeCodexAppServer();
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..selectedModelId = 'gpt-test'
        ..modelOptions = const [
          CodexModelOption(
            id: 'gpt-test',
            displayName: 'GPT Test',
            description: '',
            isDefault: true,
          ),
        ];

      await controller.sendPrompt(
        r'$documents 实现这个功能',
        goal: '完成附件菜单',
        planMode: true,
        additionalInput: const [
          {
            'type': 'skill',
            'name': 'documents',
            'path': '/skills/documents/SKILL.md',
          },
        ],
      );

      expect(server.threadGoal, '完成附件菜单');
      expect(server.startedTurnPrompt, contains(r'$documents'));
      expect(server.startedTurnAdditionalInput, [
        {
          'type': 'skill',
          'name': 'documents',
          'path': '/skills/documents/SKILL.md',
        },
      ]);
      expect(server.startedTurnCollaborationMode?['mode'], 'plan');
      controller.dispose();
    },
  );

  testWidgets('rebuilds when an explicitly injected controller changes', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    controller.createThread();
    await tester.pump();

    expect(find.text('已新建任务'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'classifies server approval requests before JSON-RPC responses',
    () async {
      final server = CodexAppServer();
      final eventFuture = server.events.first;

      server.handleStdoutLineForTesting('''
      {"id": "approval-1", "method": "item/fileChange/requestApproval",
       "params": {"threadId": "thread-1", "turnId": "turn-1"}}
    ''');

      final event = await eventFuture;
      expect(event.isServerRequest, isTrue);
      expect(event.requestId, 'approval-1');
      expect(event.method, 'item/fileChange/requestApproval');
      await server.dispose();
    },
  );

  test('tracks structured plan updates for the active turn', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'turn': {'id': 'turn-1'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-1',
          'explanation': '先核对协议，再实现界面。',
          'plan': [
            {'step': '核对协议', 'status': 'completed'},
            {'step': '实现界面', 'status': 'inProgress'},
            {'step': '运行验证', 'status': 'pending'},
          ],
        },
      ),
    );

    expect(controller.activeTurnId, 'turn-1');
    expect(controller.activeTaskPlan?.explanation, '先核对协议，再实现界面。');
    expect(controller.activeTaskPlan?.focusedStepIndex, 1);
    expect(controller.activeTaskPlan?.completedStepCount, 1);
    expect(
      controller.activeTaskPlan?.steps[1].status,
      TaskPlanStepStatus.inProgress,
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'older-turn',
          'plan': [
            {'step': '迟到的旧计划', 'status': 'inProgress'},
          ],
        },
      ),
    );
    expect(controller.activeTaskPlan?.steps.first.step, '核对协议');
    controller.dispose();
  });

  testWidgets('shows live task steps in a floating progress panel', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-1',
          'explanation': '正在按计划实现分步展示',
          'plan': [
            {'step': '更新文档', 'status': 'completed'},
            {'step': '实现进度面板', 'status': 'inProgress'},
            {'step': '运行测试', 'status': 'pending'},
          ],
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('task-plan-progress')), findsOneWidget);
    expect(find.text('正在按计划实现分步展示'), findsOneWidget);
    expect(find.text('更新文档'), findsOneWidget);
    expect(find.text('实现进度面板'), findsOneWidget);
    expect(find.text('运行测试'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('第 2 / 3 步'), findsOneWidget);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'id': 'turn-1', 'status': 'completed'},
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('task-plan-progress')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scrolls a long task plan to the newly focused step', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running;
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-long',
          'plan': List.generate(
            12,
            (index) => {
              'step': '计划步骤 ${index + 1}',
              'status': index == 0 ? 'inProgress' : 'pending',
            },
          ),
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    // A live turn includes the intentionally repeating thinking indicator.
    await tester.pump();

    final planScrollable = find.descendant(
      of: find.byKey(const Key('task-plan-progress')),
      matching: find.byType(Scrollable),
    );
    expect(planScrollable, findsOneWidget);
    expect(tester.state<ScrollableState>(planScrollable).position.pixels, 0);

    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'turnId': 'turn-long',
          'plan': List.generate(
            12,
            (index) => {
              'step': '计划步骤 ${index + 1}',
              'status': index < 9
                  ? 'completed'
                  : index == 9
                  ? 'inProgress'
                  : 'pending',
            },
          ),
        },
      ),
    );
    // Wait for the plan's scroll transition without waiting on the deliberate
    // looping thinking indicator for this active turn.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('第 10 / 12 步'), findsOneWidget);
    expect(
      tester.state<ScrollableState>(planScrollable).position.pixels,
      greaterThan(0),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('returns a scoped approval decision to App Server', () async {
    final writes = <JsonMap>[];
    final server = CodexAppServer(messageSink: writes.add);
    final controller = CodexController(server: server);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/commandExecution/requestApproval',
        requestId: 42,
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'command': 'dart test',
        },
      ),
    );
    await controller.respondToApproval(accepted: true);

    expect(writes, [
      {
        'id': 42,
        'result': {'decision': 'accept'},
      },
    ]);
    expect(controller.pendingApproval, isNull);
    controller.dispose();
  });

  test(
    'automatically approves supported requests in auto approval mode',
    () async {
      final writes = <JsonMap>[];
      final controller = CodexController(
        server: CodexAppServer(messageSink: writes.add),
      );

      await controller.setApprovalMode(ApprovalMode.autoApprove);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/fileChange/requestApproval',
          requestId: 'approval-2',
          params: {'reason': 'Update a project file'},
        ),
      );

      expect(writes, [
        {
          'id': 'approval-2',
          'result': {'decision': 'accept'},
        },
      ]);
      expect(controller.pendingApproval, isNull);
      expect(
        controller.entries.map((entry) => entry.title),
        contains('已自动批准本次操作'),
      );
      controller.dispose();
    },
  );

  test('uses the unified approval mode labels', () {
    expect(ApprovalMode.manual.label, '请求批准');
    expect(ApprovalMode.autoApprove.label, '帮我批准');
  });

  test('persists and restores the approval mode', () async {
    final store = _FakeRuntimeConfigurationStore();
    final firstController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );

    await firstController.waitForInitialConfiguration();
    await firstController.setApprovalMode(ApprovalMode.autoApprove);

    expect(store.savedApprovalMode, ApprovalMode.autoApprove.name);
    firstController.dispose();

    final restoredController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );
    await restoredController.waitForInitialConfiguration();

    expect(restoredController.approvalMode, ApprovalMode.autoApprove);
    await restoredController.setApprovalMode(ApprovalMode.manual);
    expect(store.savedApprovalMode, ApprovalMode.manual.name);
    restoredController.dispose();

    final defaultRestoredController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );
    await defaultRestoredController.waitForInitialConfiguration();

    expect(defaultRestoredController.approvalMode, ApprovalMode.manual);
    defaultRestoredController.dispose();
  });

  test('coalesces agent deltas into one timeline entry', () async {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'message-1', 'delta': 'Hello'},
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'message-1', 'delta': ' world'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final agentEntries = controller.entries
        .where((entry) => entry.kind == TimelineKind.agent)
        .toList();
    expect(agentEntries, hasLength(1));
    expect(agentEntries.single.detail, 'Hello world');
    controller.dispose();
  });

  test('tracks a live command and persists the completed turn duration', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1';

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'turn': {'id': 'turn-1', 'startedAt': 1000},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'command-1',
            'type': 'commandExecution',
            'command': 'dart test',
          },
        },
      ),
    );

    expect(controller.activeCommand, 'dart test');

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'command-1',
            'type': 'commandExecution',
            'command': 'dart test',
            'aggregatedOutput': 'All tests passed',
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'thread-1',
          'turn': {'id': 'turn-1', 'status': 'completed', 'durationMs': 63000},
        },
      ),
    );

    expect(controller.activeCommand, isNull);
    expect(controller.activeTurnId, isNull);
    expect(
      controller.entries.map((entry) => '${entry.title}:${entry.detail}'),
      containsAll(['执行命令:dart test\nAll tests passed', '耗时 1 分钟 3 秒:']),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'late-command',
            'type': 'commandExecution',
            'command': 'should not appear',
          },
        },
      ),
    );
    expect(controller.activeCommand, isNull);
    controller.dispose();
  });

  test('uses App Server item types for the live turn status', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'search-1',
            'type': 'webSearch',
            'query': 'Codex App Server protocol',
          },
        },
      ),
    );

    expect(controller.activeLiveActivity?.label, '正在搜索网页');
    expect(controller.activeLiveActivity?.detail, 'Codex App Server protocol');
    expect(controller.activeCommand, isNull);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'mcp-1',
            'type': 'mcpToolCall',
            'server': 'docs',
            'tool': 'search',
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {'id': 'search-1', 'type': 'webSearch'},
        },
      ),
    );

    expect(controller.activeLiveActivity?.label, '正在调用 MCP 工具');
    expect(controller.activeLiveActivity?.detail, 'docs/search');

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {'id': 'mcp-1', 'type': 'mcpToolCall'},
        },
      ),
    );

    expect(controller.activeLiveActivity, isNull);
    controller.dispose();
  });

  test('labels a dynamic skill reader with the skill name', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'skill-reader-1',
            'type': 'dynamicToolCall',
            'namespace': 'skills',
            'tool': 'read',
            'arguments': {'name': 'code-review'},
          },
        },
      ),
    );

    expect(controller.activeLiveActivity?.kind, 'skillRead');
    expect(controller.activeLiveActivity?.label, '正在读取 Code Review 技能');
    controller.dispose();
  });

  test('ignores lifecycle events from a previously resumed thread', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'current-thread';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'threadId': 'current-thread',
          'turn': {'id': 'current-turn'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'current-thread',
          'turnId': 'current-turn',
          'item': {
            'id': 'current-command',
            'type': 'commandExecution',
            'command': 'dart test',
          },
        },
      ),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'threadId': 'previous-thread',
          'turn': {'id': 'previous-turn'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'previous-thread',
          'turnId': 'previous-turn',
          'item': {
            'id': 'previous-file',
            'type': 'fileChange',
            'changes': [
              {'path': 'lib/other.dart', 'kind': 'modified'},
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {
          'threadId': 'previous-thread',
          'turnId': 'previous-turn',
          'diff': 'unrelated diff',
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'previous-thread',
          'turn': {
            'id': 'previous-turn',
            'status': 'completed',
            'durationMs': 63000,
          },
        },
      ),
    );

    expect(controller.status, RuntimeStatus.running);
    expect(controller.activeTurnId, 'current-turn');
    expect(controller.activeCommand, 'dart test');
    expect(controller.fileChanges, isEmpty);
    expect(controller.turnDiff, isNull);
    expect(
      controller.entries.map((entry) => entry.kind),
      isNot(contains(TimelineKind.elapsed)),
    );
    controller.dispose();
  });

  test('ignores delayed lifecycle and plan events with no active task', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'threadId': 'previous-thread',
          'turn': {'id': 'previous-turn'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'threadId': 'previous-thread',
          'turnId': 'previous-turn',
          'plan': [
            {'step': '旧任务计划', 'status': 'inProgress'},
          ],
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'previous-thread',
          'turnId': 'previous-turn',
          'item': {
            'id': 'previous-command',
            'type': 'commandExecution',
            'command': 'should not appear',
          },
        },
      ),
    );

    expect(controller.activeTurnId, isNull);
    expect(controller.activeTaskPlan, isNull);
    expect(controller.activeCommand, isNull);
    controller.dispose();
  });

  testWidgets('renders the quiet live command row and completed duration', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'turn': {'id': 'turn-1'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'command-1',
            'type': 'commandExecution',
            'command': '/bin/zsh -lc dart test',
          },
        },
      ),
    );

    expect(controller.activeTurnStartedAt, isNotNull);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('live-command-row')), findsOneWidget);
    expect(find.byKey(const Key('live-command-shimmer')), findsOneWidget);
    expect(find.byKey(const Key('live-thinking-row')), findsNothing);
    expect(find.byKey(const Key('live-elapsed-row')), findsOneWidget);
    expect(find.text('已处理 0 秒'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('live-elapsed-row')))
          .properties
          .liveRegion,
      isNot(isTrue),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已处理 1 秒'), findsOneWidget);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'command-1',
            'type': 'commandExecution',
            'command': '/bin/zsh -lc dart test',
          },
        },
      ),
    );
    await tester.pump();

    expect(controller.status, RuntimeStatus.running);
    expect(controller.activeLiveActivity, isNull);
    expect(find.byKey(const Key('live-command-row')), findsNothing);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'thread-1',
          'turn': {'id': 'turn-1', 'status': 'completed', 'durationMs': 63000},
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('live-command-row')), findsNothing);
    expect(find.byKey(const Key('live-thinking-row')), findsNothing);
    expect(find.text('耗时 1 分钟 3 秒'), findsOneWidget);
    expect(find.text('已运行了命令'), findsOneWidget);
    expect(find.text('已运行 /bin/zsh -lc dart test'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'elapsed disclosure hides process details but keeps the final answer visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: CodexAppServer());
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: '请完成任务',
          createdAt: DateTime(2026),
        ),
        TimelineEntry(
          kind: TimelineKind.command,
          title: '执行命令',
          detail: 'flutter analyze\nNo issues found',
          createdAt: DateTime(2026, 1, 1, 0, 0, 1),
        ),
        TimelineEntry(
          kind: TimelineKind.approval,
          title: '已批准命令',
          detail: 'flutter analyze',
          createdAt: DateTime(2026, 1, 1, 0, 0, 2),
        ),
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '任务已经完成。',
          createdAt: DateTime(2026, 1, 1, 0, 0, 3),
        ),
        TimelineEntry(
          kind: TimelineKind.elapsed,
          title: '耗时 4 秒',
          detail: '',
          createdAt: DateTime(2026, 1, 1, 0, 0, 4),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(find.text('已运行 flutter analyze'), findsOneWidget);
      expect(find.text('No issues found'), findsNothing);
      expect(
        tester.getTopLeft(find.text('已批准命令')).dy,
        lessThan(tester.getTopLeft(find.text('耗时 4 秒')).dy),
      );
      expect(
        tester.getTopLeft(find.text('任务已经完成。')).dy,
        lessThan(tester.getTopLeft(find.text('耗时 4 秒')).dy),
      );

      await tester.tap(
        find.byKey(const Key('completed-turn-disclosure-toggle')),
      );
      await tester.pump();

      expect(find.text('已运行 flutter analyze'), findsNothing);
      expect(find.text('已批准命令'), findsOneWidget);
      expect(find.text('任务已经完成。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('renders a plain duration when a turn has no process details', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: '请直接回答',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '这是直接回答。',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
      TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 1 秒',
        detail: '',
        createdAt: DateTime(2026, 1, 1, 0, 0, 2),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.text('这是直接回答。'), findsOneWidget);
    expect(find.text('耗时 1 秒'), findsOneWidget);
    expect(
      find.byKey(const Key('completed-turn-disclosure-toggle')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders the server-declared live activity before thinking', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'search-1',
            'type': 'webSearch',
            'query': 'Codex App Server',
          },
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('live-activity-row')), findsOneWidget);
    expect(find.byKey(const Key('live-activity-shimmer')), findsOneWidget);
    expect(find.text('正在搜索网页 Codex App Server'), findsOneWidget);
    expect(find.byKey(const Key('live-thinking-row')), findsNothing);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {'id': 'search-1', 'type': 'webSearch'},
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('live-activity-row')), findsNothing);
    expect(find.byKey(const Key('live-thinking-row')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders Codex replies as selectable Markdown', (tester) async {
    final controller = CodexController(server: CodexAppServer());
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {
          'itemId': 'markdown-message',
          'delta': '- **严重**：加密缓存每次保存会丢掉其他项目的历史。',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 60));

    final selectionArea = find.byKey(const Key('agent-markdown-selection'));
    expect(selectionArea, findsOneWidget);
    expect(
      find.descendant(of: selectionArea, matching: find.byType(Scrollable)),
      findsNothing,
    );
    final renderedText = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('严重'),
    );
    expect(renderedText, findsOneWidget);
    final text = tester.widget<RichText>(renderedText).text;
    expect(text.toPlainText(), contains('严重'));
    expect(text.toPlainText(), isNot(contains('**')));

    await tester.pumpWidget(const SizedBox());
  });

  test('opens only project-local Markdown file links', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'codex-desk-markdown-link-',
    );
    final document = File('${workspace.path}/technical-plan.md');
    await document.writeAsString('# Technical plan');
    final outside = await Directory.systemTemp.createTemp(
      'codex-desk-markdown-link-outside-',
    );
    final outsideDocument = File('${outside.path}/secret.md');
    await outsideDocument.writeAsString('# Outside');
    final indirectDocument = Link('${workspace.path}/indirect.md');
    await indirectDocument.create(outsideDocument.path);
    addTearDown(() async {
      await workspace.delete(recursive: true);
      await outside.delete(recursive: true);
    });

    Uri? opened;
    final didOpen = await openAgentMarkdownLink(
      href: 'technical-plan.md',
      workspacePath: workspace.path,
      launch: (uri) async {
        opened = uri;
        return true;
      },
    );

    expect(didOpen, isTrue);
    expect(opened, Uri.file(await document.resolveSymbolicLinks()));

    final didOpenOutside = await openAgentMarkdownLink(
      href: outsideDocument.uri.toString(),
      workspacePath: workspace.path,
      launch: (_) async => fail('must not open files outside the workspace'),
    );

    expect(didOpenOutside, isFalse);

    final didOpenIndirect = await openAgentMarkdownLink(
      href: 'indirect.md',
      workspacePath: workspace.path,
      launch: (_) async => fail('must not follow a link outside the workspace'),
    );

    expect(didOpenIndirect, isFalse);
  });

  test('keeps command output delta protocol events out of the timeline', () {
    final controller = CodexController(server: CodexAppServer());
    final initialEntryCount = controller.entries.length;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/commandExecution/outputDelta',
        params: {'itemId': 'command-1', 'delta': 'Compiling...'},
      ),
    );

    expect(controller.entries, hasLength(initialEntryCount));
    expect(controller.entries.where((entry) => entry.title == '执行事件'), isEmpty);
    controller.dispose();
  });

  test('refuses to switch workspaces while a turn is running', () async {
    final controller = CodexController(server: CodexAppServer());
    controller
      ..workspacePath = '/original/workspace'
      ..status = RuntimeStatus.running;

    await controller.selectWorkspace('/private/tmp');

    expect(controller.workspacePath, '/original/workspace');
    expect(controller.lastError, contains('先停止当前运行时'));
    controller.dispose();
  });

  test('refuses the system temporary directory as a workspace', () async {
    final controller = CodexController(server: CodexAppServer());

    await controller.selectWorkspace(Directory.systemTemp.path);

    expect(controller.workspacePath, isNull);
    expect(controller.lastError, contains('系统临时目录'));
    expect(runtimeConfigurationStore.savedWorkspace, isNull);
    controller.dispose();
  });

  test('cleans a persisted system temporary directory workspace', () async {
    final temporaryPath = await Directory.systemTemp.resolveSymbolicLinks();
    final store = _FakeRuntimeConfigurationStore()
      ..workspace = temporaryPath
      ..workspaces = [WorkspaceConfiguration(primaryPath: temporaryPath)];
    final controller = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );

    await controller.waitForInitialConfiguration();

    expect(controller.workspacePath, isNull);
    expect(controller.workspaceConfigurations, isEmpty);
    expect(store.clearedWorkspace, isTrue);
    expect(store.savedWorkspaces, isEmpty);
    controller.dispose();
  });

  test('persists and restores the most recently selected workspace', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'codex-desk-persisted-workspace-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final store = _FakeRuntimeConfigurationStore();
    final firstController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );

    await firstController.selectWorkspace(workspace.path);

    expect(store.savedWorkspace, firstController.workspacePath);
    firstController.dispose();

    final restoredController = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );
    await restoredController.waitForInitialConfiguration();

    expect(restoredController.workspacePath, store.savedWorkspace);
    restoredController.dispose();
  });

  test(
    'creates switchable workspaces with independent additional directories',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-workspace-profiles-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory(
        '${root.path}/first',
      ).create(recursive: true);
      final firstAdditional = await Directory(
        '${root.path}/first-shared',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second',
      ).create(recursive: true);
      final secondAdditional = await Directory(
        '${root.path}/second-shared',
      ).create(recursive: true);
      final store = _FakeRuntimeConfigurationStore();
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();

      await controller.selectWorkspace(first.path);
      await controller.addWorkspaceRoot(firstAdditional.path);
      await controller.selectWorkspace(second.path);
      await controller.addWorkspaceRoot(secondAdditional.path);

      expect(controller.workspaceConfigurations, hasLength(2));
      expect(controller.additionalWorkspacePaths, [
        await secondAdditional.resolveSymbolicLinks(),
      ]);

      await controller.selectWorkspace(first.path);

      expect(controller.additionalWorkspacePaths, [
        await firstAdditional.resolveSymbolicLinks(),
      ]);
      expect(
        controller.workspaceConfigurations
            .map((workspace) => workspace.primaryPath)
            .toList(),
        [
          await first.resolveSymbolicLinks(),
          await second.resolveSymbolicLinks(),
        ],
      );
      expect(store.savedWorkspaces, hasLength(2));
      controller.dispose();

      final restoredController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await restoredController.waitForInitialConfiguration();

      expect(
        restoredController.workspacePath,
        await first.resolveSymbolicLinks(),
      );
      expect(restoredController.additionalWorkspacePaths, [
        await firstAdditional.resolveSymbolicLinks(),
      ]);
      await restoredController.selectWorkspace(second.path);
      expect(restoredController.additionalWorkspacePaths, [
        await secondAdditional.resolveSymbolicLinks(),
      ]);
      await restoredController.selectWorkspace(first.path);
      expect(
        restoredController.workspaceConfigurations
            .map((workspace) => workspace.primaryPath)
            .toList(),
        [
          await first.resolveSymbolicLinks(),
          await second.resolveSymbolicLinks(),
        ],
      );

      await restoredController.forgetWorkspace(
        await second.resolveSymbolicLinks(),
      );
      expect(restoredController.workspaceConfigurations, hasLength(1));
      expect(
        restoredController.workspacePath,
        await first.resolveSymbolicLinks(),
      );
      restoredController.dispose();
    },
  );

  test(
    'starts a newly created project with no inherited directory tasks',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-desk-clean-project-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final server = _ManagedRuntimeFakeServer()
        ..listResponse = [
          {'id': 'older-directory-task', 'preview': '来自同一目录的旧任务'},
        ];
      final history = _MemoryConversationHistoryStore();
      final controller = CodexController(
        server: server,
        conversationHistoryStore: history,
      );
      await controller.waitForInitialConfiguration();

      await controller.createWorkspace(directory.path);
      await controller.refreshThreads();

      expect(controller.threads, isEmpty);
      expect(controller.workspaceProjectId, isNotNull);

      server.listResponse = [
        {'id': 'new-thread', 'preview': '这个项目的新任务'},
      ];
      controller.status = RuntimeStatus.ready;
      expect(await controller.sendPrompt('创建任务'), isTrue);
      expect(controller.threads.map((thread) => thread.id), ['new-thread']);

      controller.dispose();
    },
  );

  test(
    'switches to an inactive task workspace before resuming its task',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-open-cached-task-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      final server = _ManagedRuntimeFakeServer();
      final controller = CodexController(server: server);
      await controller.waitForInitialConfiguration();

      expect(await controller.createWorkspace(first.path), isTrue);
      expect(await controller.createWorkspace(second.path), isTrue);
      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      final secondPath = await second.resolveSymbolicLinks();

      await controller.openWorkspaceThread(
        workspace: secondPath,
        thread: _thread(id: 'second-project-thread'),
      );

      expect(controller.workspacePath, secondPath);
      expect(server.runtimeDirectory, secondPath);
      expect(server.resumedThreadId, 'second-project-thread');
      controller.dispose();
    },
  );

  test('automatically connects a restored primary workspace', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-auto-restore-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = _ManagedRuntimeFakeServer()
      ..listResponse = [
        {'id': 'connected-thread', 'preview': 'connected'},
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore()
        ..workspace = primary.path,
    );

    await controller.connectRestoredWorkspace();

    expect(controller.status, RuntimeStatus.ready);
    expect(server.startCalls, 1);
    expect(server.runtimeDirectory, await primary.resolveSymbolicLinks());
    controller.dispose();
  });

  test(
    'automatically reconnects after changing the primary workspace',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-auto-switch-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = await Directory(
        '${root.path}/first',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second',
      ).create(recursive: true);
      final additional = await Directory(
        '${root.path}/additional',
      ).create(recursive: true);
      final server = _ManagedRuntimeFakeServer()
        ..listResponse = [
          {'id': 'connected-thread', 'preview': 'connected'},
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();

      expect(await controller.selectWorkspaceAndReconnect(first.path), isTrue);
      expect(controller.status, RuntimeStatus.ready);
      expect(server.startCalls, 1);
      expect(server.stopCalls, 0);

      await controller.addWorkspaceRoot(additional.path);
      expect(server.stopCalls, 0);
      expect(await controller.selectWorkspaceAndReconnect(second.path), isTrue);
      expect(controller.status, RuntimeStatus.ready);
      expect(server.stopCalls, 1);
      expect(server.startCalls, 2);
      expect(server.runtimeDirectory, await second.resolveSymbolicLinks());
      expect(controller.workspaceConfigurations, hasLength(2));
      expect(controller.additionalWorkspacePaths, isEmpty);

      controller.status = RuntimeStatus.running;
      expect(await controller.selectWorkspaceAndReconnect(first.path), isFalse);
      expect(controller.workspacePath, await second.resolveSymbolicLinks());
      expect(controller.lastError, contains('等待当前任务完成'));
      expect(server.stopCalls, 1);
      controller.dispose();
    },
  );

  test('reconnects after a successful CLI recheck from failure', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-runtime-recheck-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = _ManagedRuntimeFakeServer()
      ..listResponse = [
        {'id': 'connected-thread', 'preview': 'connected'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = primary.path
      ..status = RuntimeStatus.failed;

    await controller.inspectRuntime();

    expect(controller.status, RuntimeStatus.ready);
    expect(server.startCalls, 1);
    controller.dispose();
  });

  test('automatically reconnects after an unexpected runtime exit', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-runtime-exit-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = _ManagedRuntimeFakeServer()
      ..listResponse = [
        {'id': 'connected-thread', 'preview': 'connected'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = primary.path
      ..status = RuntimeStatus.ready;

    controller.handleServerEventForTesting(
      const ServerEvent(method: 'runtime/exited', params: {'code': 1}),
    );
    expect(controller.status, RuntimeStatus.failed);

    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(controller.status, RuntimeStatus.ready);
    expect(server.startCalls, 1);
    controller.dispose();
  });

  test('cancels an in-flight automatic connection on dispose', () async {
    final primary = await Directory.systemTemp.createTemp(
      'codex-desk-runtime-dispose-',
    );
    addTearDown(() => primary.delete(recursive: true));
    final server = _BlockingRuntimeFakeServer();
    final controller = CodexController(server: server)
      ..workspacePath = primary.path;

    final connection = controller.startRuntime();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, RuntimeStatus.starting);
    controller.dispose();
    server.probeCompleter.complete(const CodexRuntimeProbe(isAvailable: true));

    await connection;

    expect(server.startCalls, 0);
  });

  test(
    'restores, canonicalizes, and deduplicates additional workspaces',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-workspaces-',
      );
      addTearDown(() => root.delete(recursive: true));
      final primary = await Directory(
        '${root.path}/primary',
      ).create(recursive: true);
      final additional = await Directory(
        '${root.path}/additional',
      ).create(recursive: true);
      final alias = Link('${root.path}/additional-alias');
      await alias.create(additional.path);
      final store = _FakeRuntimeConfigurationStore()
        ..workspace = primary.path
        ..additionalWorkspaces = [
          additional.path,
          alias.path,
          '${root.path}/missing',
          primary.path,
        ];

      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();

      expect(controller.workspacePath, await primary.resolveSymbolicLinks());
      expect(controller.additionalWorkspacePaths, [
        await additional.resolveSymbolicLinks(),
      ]);
      expect(store.savedAdditionalWorkspaces, [
        await additional.resolveSymbolicLinks(),
      ]);
      expect(controller.workspaceConfigurations, hasLength(1));
      expect(controller.workspaceConfigurations.single.additionalPaths, [
        await additional.resolveSymbolicLinks(),
      ]);
      expect(store.savedWorkspaces, hasLength(1));
      controller.dispose();
    },
  );

  test(
    'adds and removes additional directories without disconnecting runtime',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-workspace-add-',
      );
      addTearDown(() => root.delete(recursive: true));
      final primary = await Directory(
        '${root.path}/primary',
      ).create(recursive: true);
      final first = await Directory(
        '${root.path}/first',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second',
      ).create(recursive: true);
      final store = _FakeRuntimeConfigurationStore();
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();

      await controller.selectWorkspace(primary.path);
      await controller.addWorkspaceRoot(first.path);
      await controller.addWorkspaceRoot(second.path);
      await controller.addWorkspaceRoot(first.path);

      expect(controller.workspaceRoots, [
        await primary.resolveSymbolicLinks(),
        await first.resolveSymbolicLinks(),
        await second.resolveSymbolicLinks(),
      ]);
      expect(
        store.savedAdditionalWorkspaces,
        controller.additionalWorkspacePaths,
      );

      controller.status = RuntimeStatus.ready;
      await controller.removeWorkspaceRoot(
        controller.additionalWorkspacePaths.first,
      );
      expect(controller.additionalWorkspacePaths, [
        await second.resolveSymbolicLinks(),
      ]);
      expect(store.savedAdditionalWorkspaces, [
        await second.resolveSymbolicLinks(),
      ]);
      controller.dispose();
    },
  );

  test('serializes additional workspace persistence snapshots', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-workspace-save-',
    );
    addTearDown(() => root.delete(recursive: true));
    final primary = await Directory(
      '${root.path}/primary',
    ).create(recursive: true);
    final first = await Directory('${root.path}/first').create(recursive: true);
    final second = await Directory(
      '${root.path}/second',
    ).create(recursive: true);
    final store = _DelayedAdditionalWorkspaceStore();
    final controller = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    )..workspacePath = primary.path;
    await controller.waitForInitialConfiguration();

    final firstSave = controller.addWorkspaceRoot(first.path);
    while (store.saveCompleters.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final secondSave = controller.addWorkspaceRoot(second.path);
    await Future<void>.delayed(Duration.zero);

    expect(store.savedSnapshots, [
      [await first.resolveSymbolicLinks()],
    ]);

    store.saveCompleters.first.complete();
    while (store.saveCompleters.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(store.savedSnapshots.last, [
      await first.resolveSymbolicLinks(),
      await second.resolveSymbolicLinks(),
    ]);
    store.saveCompleters.last.complete();
    await Future.wait([firstSave, secondSave]);
    controller.dispose();
  });

  testWidgets('manages primary and additional workspace directories', (
    tester,
  ) async {
    late Directory root;
    late String additionalPath;
    late String secondPath;
    late CodexController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'codex-desk-workspace-dialog-',
      );
      final primary = await Directory(
        '${root.path}/primary',
      ).create(recursive: true);
      final additional = await Directory(
        '${root.path}/additional',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second',
      ).create(recursive: true);
      additionalPath = await additional.resolveSymbolicLinks();
      secondPath = await second.resolveSymbolicLinks();
      controller = CodexController(
        server: _ManagedRuntimeFakeServer(),
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore()
          ..workspace = primary.path
          ..additionalWorkspaces = [additional.path]
          ..workspaces = [
            WorkspaceConfiguration(
              primaryPath: primary.path,
              additionalPaths: [additional.path],
            ),
            WorkspaceConfiguration(primaryPath: second.path),
          ],
      );
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.running;
    });
    addTearDown(() => root.delete(recursive: true));
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-manage-workspaces-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const Key('workspace-directories-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('主目录'), findsWidgets);
    expect(find.text(additionalPath), findsOneWidget);
    expect(find.text('附加目录'), findsWidgets);
    expect(find.text('新建工作区'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('create-workspace-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(ValueKey('switch-workspace-$secondPath')),
          )
          .onPressed,
      isNull,
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('create-workspace-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(ValueKey('switch-workspace-$secondPath')),
          )
          .onPressed,
      isNotNull,
    );

    final removeAdditional = find.byTooltip('移除附加目录');
    await tester.ensureVisible(removeAdditional);
    await tester.pump();
    await tester.tap(removeAdditional);
    await tester.pump();
    expect(controller.additionalWorkspacePaths, isEmpty);
    expect(
      find.byKey(const Key('additional-workspaces-empty')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'restores cached conversation history for the selected workspace',
    () async {
      final workspaceDirectory = await Directory.systemTemp.createTemp(
        'codex-desk-cached-history-',
      );
      addTearDown(() => workspaceDirectory.delete(recursive: true));
      final runtimeStore = _FakeRuntimeConfigurationStore();
      final firstController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await firstController.selectWorkspace(workspaceDirectory.path);
      firstController
        ..threads = [_thread(id: 'cached-thread')]
        ..activeThreadId = 'cached-thread'
        ..handleServerEventForTesting(
          const ServerEvent(
            method: 'item/completed',
            params: {
              'item': {
                'type': 'fileChange',
                'changes': [
                  {
                    'path': 'lib/main.dart',
                    'kind': 'modified',
                    'diff': '+cached',
                  },
                ],
              },
            },
          ),
        );
      await firstController.saveConversationHistoryForTesting();
      final workspace = firstController.workspacePath!;
      firstController.dispose();

      final restoredController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await restoredController.waitForInitialConfiguration();

      expect(restoredController.workspacePath, workspace);
      expect(restoredController.threads.map((thread) => thread.id), [
        'cached-thread',
      ]);
      expect(restoredController.activeThreadId, 'cached-thread');
      expect(restoredController.fileChanges.single.diff, '+cached');
      expect(
        restoredController.entries.map((entry) => entry.title),
        isNot(contains('文件变更')),
      );
      restoredController.dispose();
    },
  );

  test(
    'migrates path-keyed history when a project ID was saved before migration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-desk-history-key-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final workspace = await directory.resolveSymbolicLinks();
      const projectId = 'project-partially-migrated';
      historyStore.snapshots[workspace] = ConversationHistorySnapshot(
        threads: [_thread(id: 'legacy-thread')],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
      );
      final runtimeStore = _FakeRuntimeConfigurationStore()
        ..workspace = workspace
        ..workspaces = [
          WorkspaceConfiguration(id: projectId, primaryPath: workspace),
        ];

      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await controller.waitForInitialConfiguration();

      expect(controller.threads.map((thread) => thread.id), ['legacy-thread']);
      expect(
        historyStore.snapshots[projectId]!.threads.map((thread) => thread.id),
        ['legacy-thread'],
      );
      controller.dispose();

      final restartedController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );
      await restartedController.waitForInitialConfiguration();
      expect(restartedController.threads.map((thread) => thread.id), [
        'legacy-thread',
      ]);
      restartedController.dispose();
    },
  );

  test('preserves a project ID while editing its folders and name', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-project-id-',
    );
    addTearDown(() => root.delete(recursive: true));
    final primary = await Directory('${root.path}/primary').create();
    final additional = await Directory('${root.path}/additional').create();
    final primaryPath = await primary.resolveSymbolicLinks();
    final additionalPath = await additional.resolveSymbolicLinks();
    const projectId = 'stable-project-id';
    final store = _FakeRuntimeConfigurationStore()
      ..workspace = primaryPath
      ..workspaces = [
        WorkspaceConfiguration(id: projectId, primaryPath: primaryPath),
      ];
    final controller = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: store,
    );
    await controller.waitForInitialConfiguration();

    await controller.renameWorkspace(primaryPath, 'Renamed project');
    expect(store.savedWorkspaces!.single.id, projectId);

    await controller.addWorkspaceRoot(additionalPath);
    expect(store.savedWorkspaces!.single.id, projectId);

    await controller.removeWorkspaceRoot(additionalPath);
    expect(store.savedWorkspaces!.single.id, projectId);
    controller.dispose();
  });

  test(
    'persists pinned task IDs with each workspace history snapshot',
    () async {
      final controller =
          CodexController(
              server: CodexAppServer(),
              conversationHistoryStore: historyStore,
            )
            ..workspacePath = '/workspace'
            ..threads = [_thread(id: 'first'), _thread(id: 'second')];

      controller.toggleThreadPinned(controller.threads.last);
      await controller.acknowledgeCompletedThread('first');
      await controller.saveConversationHistoryForTesting();

      expect(historyStore.snapshots['/workspace']!.pinnedThreadIds, {'second'});
      expect(
        historyStore.snapshots['/workspace']!.acknowledgedCompletedThreadIds,
        {'first'},
      );
      controller.dispose();
    },
  );

  test(
    'continues the restored thread after reconnecting the runtime',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'codex-restored-thread-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final canonicalWorkspace = await workspace.resolveSymbolicLinks();
      final runtimeStore = _FakeRuntimeConfigurationStore()
        ..workspace = canonicalWorkspace;
      historyStore.snapshots[canonicalWorkspace] = ConversationHistorySnapshot(
        threads: [_thread(id: 'restored-thread')],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
        activeThreadId: 'restored-thread',
      );
      final server = _ManagedRuntimeFakeServer()
        ..listResponse = [
          {'id': 'restored-thread', 'preview': 'restored'},
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
      );

      await controller.waitForInitialConfiguration();
      await controller.startRuntime();
      expect(server.resumedThreadId, 'restored-thread');
      expect(controller.activeThreadId, 'restored-thread');

      await controller.sendPrompt('继续上一轮');
      expect(server.startedTurnThreadId, 'restored-thread');
      expect(server.startedThreadDirectory, isNull);
      controller.dispose();
    },
  );

  test(
    'keeps a cached active thread when both runtime lists are temporarily empty',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'codex-empty-thread-list-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final canonicalWorkspace = await workspace.resolveSymbolicLinks();
      final runtimeStore = _FakeRuntimeConfigurationStore()
        ..workspace = canonicalWorkspace;
      historyStore.snapshots[canonicalWorkspace] = ConversationHistorySnapshot(
        threads: [_thread(id: 'cached-active-thread')],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
        activeThreadId: 'cached-active-thread',
      );
      final server = _ManagedRuntimeFakeServer()..listResponse = const [];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: runtimeStore,
        conversationHistoryStore: historyStore,
        localSessionThreadStore: _MemoryLocalSessionThreadStore(),
      );

      await controller.waitForInitialConfiguration();
      await controller.startRuntime();

      expect(server.resumedThreadId, 'cached-active-thread');
      expect(controller.canSend, isTrue);
      controller.dispose();
    },
  );

  test(
    'does not retain pinned tasks when switching to a fresh workspace',
    () async {
      final firstWorkspace = await Directory.systemTemp.createTemp(
        'codex-history-first-',
      );
      final secondWorkspace = await Directory.systemTemp.createTemp(
        'codex-history-second-',
      );
      addTearDown(() => firstWorkspace.delete(recursive: true));
      addTearDown(() => secondWorkspace.delete(recursive: true));
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
        conversationHistoryStore: historyStore,
      );

      await controller.selectWorkspace(firstWorkspace.path);
      controller.threads = [_thread(id: 'first-thread')];
      controller.toggleThreadPinned(controller.threads.single);
      await controller.selectWorkspace(secondWorkspace.path);

      expect(controller.pinnedThreadIds, isEmpty);
      controller.dispose();
    },
  );

  test(
    'does not retain acknowledged completions when creating a fresh workspace',
    () async {
      final firstWorkspace = await Directory.systemTemp.createTemp(
        'codex-acknowledged-first-',
      );
      final secondWorkspace = await Directory.systemTemp.createTemp(
        'codex-acknowledged-second-',
      );
      addTearDown(() => firstWorkspace.delete(recursive: true));
      addTearDown(() => secondWorkspace.delete(recursive: true));
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
        conversationHistoryStore: historyStore,
      );

      await controller.selectWorkspace(firstWorkspace.path);
      await controller.acknowledgeCompletedThread('completed-in-first');
      final snapshotKeysBeforeSecondWorkspace = Set<String>.of(
        historyStore.snapshots.keys,
      );
      await controller.selectWorkspace(secondWorkspace.path);

      expect(
        controller.isCompletedThreadAcknowledged('completed-in-first'),
        isFalse,
      );
      final secondWorkspaceSnapshotKey = historyStore.snapshots.keys.firstWhere(
        (key) => !snapshotKeysBeforeSecondWorkspace.contains(key),
      );
      expect(
        historyStore
            .snapshots[secondWorkspaceSnapshotKey]!
            .acknowledgedCompletedThreadIds,
        isEmpty,
      );
      controller.dispose();
    },
  );

  test(
    'exports and imports portable local history without changing workspace',
    () async {
      final source =
          CodexController(
              server: CodexAppServer(),
              conversationHistoryStore: historyStore,
            )
            ..workspacePath = '/source'
            ..threads = [
              _thread(id: 'pinned-thread'),
              _thread(id: 'plain-thread'),
            ];
      source.toggleThreadPinned(source.threads.first);
      await source.acknowledgeCompletedThread('plain-thread');
      final exported = source.exportConversationHistory();

      final target = CodexController(
        server: CodexAppServer(),
        conversationHistoryStore: historyStore,
      )..workspacePath = '/target';
      await target.acknowledgeCompletedThread('pinned-thread');
      await target.importConversationHistory(exported);

      expect(target.workspacePath, '/target');
      expect(target.threads.map((thread) => thread.id), [
        'pinned-thread',
        'plain-thread',
      ]);
      expect(target.isThreadPinned('pinned-thread'), isTrue);
      expect(target.isCompletedThreadAcknowledged('plain-thread'), isTrue);
      expect(target.isCompletedThreadAcknowledged('pinned-thread'), isFalse);
      expect(jsonDecode(exported)['format'], 'codex-desk-history');
      expect(historyStore.snapshots['/target']!.pinnedThreadIds, {
        'pinned-thread',
      });
      expect(
        historyStore.snapshots['/target']!.acknowledgedCompletedThreadIds,
        {'plain-thread'},
      );
      source.dispose();
      target.dispose();
    },
  );

  testWidgets('searches tasks from the top toolbar command surface', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [_thread(id: 'alpha'), _thread(id: 'bravo')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final taskTile = find.byKey(const ValueKey('sidebar-thread-tile-alpha'));
    final taskContent = tester.widget<Padding>(
      find.descendant(of: taskTile, matching: find.byType(Padding)).first,
    );
    expect(taskContent.padding, const EdgeInsets.fromLTRB(30, 4, 8, 4));

    expect(find.byKey(const Key('thread-search-field')), findsNothing);
    await tester.tap(find.byKey(const Key('task-search-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-search-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('task-search-dialog-field')),
      'bravo',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('task-search-result-bravo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task-search-result-alpha')),
      findsNothing,
    );
    expect(find.text('新聊天'), findsOneWidget);
    expect(find.text('打开文件夹'), findsOneWidget);
    expect(find.text('搜索文件'), findsOneWidget);
  });

  testWidgets(
    'shows task hover shortcuts and opens task actions on right click',
    (tester) async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..threads = [_thread(id: 'alpha')];
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final taskTile = find.byKey(const ValueKey('sidebar-thread-tile-alpha'));
      expect(
        find.byKey(const ValueKey('sidebar-thread-pin-alpha')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sidebar-thread-archive-alpha')),
        findsNothing,
      );
      expect(
        find.descendant(of: taskTile, matching: find.byType(PopupMenuButton)),
        findsNothing,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.moveTo(tester.getCenter(taskTile));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('sidebar-thread-pin-alpha')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sidebar-thread-archive-alpha')),
        findsOneWidget,
      );

      final contextMenuMouse = await tester.createGesture(
        pointer: 2,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await contextMenuMouse.down(tester.getCenter(taskTile));
      await contextMenuMouse.up();
      await tester.pumpAndSettle();
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('归档'), findsOneWidget);
      expect(find.text('永久删除'), findsOneWidget);

      await tester.tap(find.text('置顶'));
      await tester.pump();
      expect(controller.isThreadPinned('alpha'), isTrue);
    },
  );

  testWidgets('keeps the task list visible while a selected task refreshes', (
    tester,
  ) async {
    final server = _FakeCodexAppServer()
      ..queueListRequests = true
      ..listResponse = [
        {'id': 'alpha', 'preview': 'preview-alpha'},
        {'id': 'bravo', 'preview': 'preview-bravo'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [_thread(id: 'alpha'), _thread(id: 'bravo')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.text('preview-alpha'));
    await tester.pump();

    expect(controller.threadsLoading, isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-pane')),
        matching: find.text('preview-alpha'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-pane')),
        matching: find.text('preview-bravo'),
      ),
      findsOneWidget,
    );

    server.listRequests.single.complete(server.listResponse);
    await tester.pumpAndSettle();
  });

  test(
    'uses the authoritative App Server thread list after reconnecting',
    () async {
      final server = _FakeCodexAppServer()..listResponse = [];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..threads = [_thread(id: 'cached-thread')];

      await controller.refreshThreads();

      expect(controller.threads, isEmpty);
      controller.dispose();
    },
  );

  test(
    'falls back to local Codex sessions when App Server lists none',
    () async {
      final localSessions = _MemoryLocalSessionThreadStore()
        ..threadsByWorkspace['/workspace'] = [_thread(id: 'local-thread')];
      final controller = CodexController(
        server: _FakeCodexAppServer()..listResponse = [],
        localSessionThreadStore: localSessions,
      )..workspacePath = '/workspace';

      await controller.refreshThreads();

      expect(controller.threads.single.id, 'local-thread');
      controller.dispose();
    },
  );

  test('reads a workspace thread from local Codex session metadata', () async {
    final directory = await Directory.systemTemp.createTemp('codex-sessions-');
    addTearDown(() => directory.delete(recursive: true));
    final sessionDirectory = Directory('${directory.path}/2026/08/20');
    await sessionDirectory.create(recursive: true);
    await File('${sessionDirectory.path}/rollout.jsonl').writeAsString(
      '${jsonEncode({
        'type': 'session_meta',
        'payload': {'session_id': 'local-thread', 'timestamp': '2026-08-20T00:00:00.000Z', 'cwd': '/workspace', 'model_provider': 'openai'},
      })}\n',
    );

    final threads = await LocalSessionThreadStore(
      directory: directory,
    ).listThreads('/workspace');

    expect(threads.single.id, 'local-thread');
    expect(threads.single.modelProvider, 'openai');
  });

  test('lists, installs, and toggles local Codex plugins', () async {
    final pluginStore = _MemoryCodexPluginStore()
      ..plugins.addAll([
        const CodexPlugin(
          id: 'installed@local',
          name: 'installed',
          marketplaceName: 'local',
          installed: true,
          enabled: true,
        ),
        const CodexPlugin(
          id: 'available@local',
          name: 'available',
          marketplaceName: 'local',
          installed: false,
          enabled: false,
        ),
      ]);
    final controller = CodexController(pluginStore: pluginStore);

    await controller.refreshPlugins();
    await controller.setPluginEnabled(controller.plugins.first, false);
    await controller.installPlugin(controller.plugins.last);
    await controller.addLocalPluginMarketplace('/plugins');

    expect(pluginStore.enabledChanges, {'installed@local': false});
    expect(pluginStore.installedPluginIds, ['available@local']);
    expect(pluginStore.addedMarketplaces, ['/plugins']);
    expect(
      controller.plugins
          .singleWhere((plugin) => plugin.id == 'available@local')
          .installed,
      true,
    );
    controller.dispose();
  });

  test('manages Codex marketplaces and uninstalls plugins', () async {
    const marketplace = CodexMarketplace(
      name: 'team-tools',
      root: '/plugins/team-tools',
      sourceType: 'git',
      source: 'example-org/team-tools',
    );
    final pluginStore = _MemoryCodexPluginStore()
      ..plugins.add(
        const CodexPlugin(
          id: 'sample@team-tools',
          name: 'sample',
          marketplaceName: 'team-tools',
          installed: true,
          enabled: true,
        ),
      )
      ..marketplaces.add(marketplace);
    final controller = CodexController(pluginStore: pluginStore);

    await controller.refreshPlugins();
    await controller.refreshMarketplaces();
    await controller.addPluginMarketplace('example-org/new-tools');
    await controller.upgradePluginMarketplace('team-tools');
    await controller.removePlugin(controller.plugins.single);
    await controller.removePluginMarketplace(marketplace);

    expect(pluginStore.addedMarketplaces, ['example-org/new-tools']);
    expect(pluginStore.upgradedMarketplaceNames, ['team-tools']);
    expect(pluginStore.removedPluginIds, ['sample@team-tools']);
    expect(pluginStore.removedMarketplaceNames, ['team-tools']);
    controller.dispose();
  });

  test(
    'reports plugin progress, completion, and restart requirement',
    () async {
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: false,
        enabled: false,
      );
      final pluginStore = _BlockingCodexPluginStore()..plugins.add(plugin);
      final controller = CodexController(pluginStore: pluginStore);

      final install = controller.installPlugin(plugin);
      await Future<void>.delayed(Duration.zero);

      expect(controller.pluginSaving, isTrue);
      expect(controller.pluginActionTargetId, plugin.id);
      expect(controller.pluginActionProgress, '正在安装插件 sample…');
      expect(controller.pluginRuntimeRestartRequired, isFalse);

      pluginStore.installCompleter.complete();
      await install;

      expect(controller.pluginSaving, isFalse);
      expect(controller.pluginActionProgress, isNull);
      expect(controller.pluginActionResult, contains('重启运行时'));
      expect(controller.pluginRuntimeRestartRequired, isTrue);
      controller.dispose();
    },
  );

  test(
    'automatically reconnects after a plugin configuration change',
    () async {
      final primary = await Directory.systemTemp.createTemp(
        'codex-desk-plugin-reconnect-',
      );
      addTearDown(() => primary.delete(recursive: true));
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: false,
        enabled: false,
      );
      final pluginStore = _MemoryCodexPluginStore()..plugins.add(plugin);
      final server = _ManagedRuntimeFakeServer()
        ..listResponse = [
          {'id': 'connected-thread', 'preview': 'connected'},
        ];
      final controller = CodexController(
        server: server,
        pluginStore: pluginStore,
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      await controller.selectWorkspaceAndReconnect(primary.path);

      await controller.installPlugin(plugin);

      expect(server.stopCalls, 1);
      expect(server.startCalls, 2);
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.pluginRuntimeRestartRequired, isFalse);
      expect(controller.pluginActionResult, contains('运行时已重启'));
      controller.dispose();
    },
  );

  test('keeps the plugin CLI failure reason in action feedback', () async {
    const plugin = CodexPlugin(
      id: 'sample@local',
      name: 'sample',
      marketplaceName: 'local',
      installed: false,
      enabled: false,
    );
    final controller = CodexController(
      pluginStore: _FailingCodexPluginStore()..plugins.add(plugin),
    );

    await controller.installPlugin(plugin);

    expect(controller.pluginsError, contains('安装插件 sample失败'));
    expect(controller.pluginsError, contains('marketplace 无法访问'));
    expect(controller.pluginRuntimeRestartRequired, isFalse);
    controller.dispose();
  });

  test(
    'keeps a pending restart notice when a later plugin action fails',
    () async {
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: false,
        enabled: false,
      );
      final controller = CodexController(
        pluginStore: _FailOnSecondInstallCodexPluginStore()
          ..plugins.add(plugin),
      );

      await controller.installPlugin(plugin);
      final pendingRestartNotice = controller.pluginActionResult;
      await controller.installPlugin(plugin);

      expect(controller.pluginsError, contains('second install failed'));
      expect(controller.pluginRuntimeRestartRequired, isTrue);
      expect(controller.pluginActionResult, pendingRestartNotice);
      expect(controller.pluginActionResult, contains('重启运行时'));
      controller.dispose();
    },
  );

  test('rejects malformed plugin list JSON from the Codex CLI', () async {
    final store = CodexPluginStore(
      executableProvider: () => 'codex-test',
      processRunner: (executable, arguments) async =>
          ProcessResult(1, 0, '{"installed":"invalid","available":[]}', ''),
    );

    await expectLater(store.listPlugins(), throwsFormatException);
  });

  test('resolves the CLI path before running plugin commands', () async {
    const resolvedPath = '/Applications/ChatGPT.app/Contents/Resources/codex';
    String? launchedExecutable;
    final store = CodexPluginStore(
      executableProvider: () async => resolvedPath,
      processRunner: (executable, arguments) async {
        launchedExecutable = executable;
        return ProcessResult(1, 0, '{"installed":[],"available":[]}', '');
      },
    );

    await store.listPlugins();

    expect(launchedExecutable, resolvedPath);
  });

  test('preserves Codex CLI stderr when a plugin command fails', () async {
    const plugin = CodexPlugin(
      id: 'sample@local',
      name: 'sample',
      marketplaceName: 'local',
      installed: false,
      enabled: false,
    );
    final store = CodexPluginStore(
      executableProvider: () => 'codex-test',
      processRunner: (executable, arguments) async =>
          ProcessResult(1, 9, '', 'marketplace signature invalid'),
    );

    await expectLater(
      store.installPlugin(plugin),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'marketplace signature invalid',
        ),
      ),
    );
  });

  test(
    'writes only the selected plugin enabled state to Codex config',
    () async {
      final codexHome = await Directory.systemTemp.createTemp('codex-config-');
      addTearDown(() => codexHome.delete(recursive: true));
      final config = File('${codexHome.path}/config.toml');
      await config.writeAsString(
        'model = "gpt-5"\n\n'
        '[plugins."sample@local"] # 本地测试插件\n'
        'enabled = true # 需要保留的说明\n\n'
        '[features]\n'
        'web_search = true\n',
      );
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: true,
        enabled: true,
      );

      await CodexPluginStore(
        codexHome: codexHome,
      ).setPluginEnabled(plugin, false);

      expect(
        await config.readAsString(),
        'model = "gpt-5"\n\n'
        '[plugins."sample@local"] # 本地测试插件\n'
        'enabled = false # 需要保留的说明\n\n'
        '[features]\n'
        'web_search = true\n',
      );
    },
  );

  test(
    'creates a missing Codex config directory with an atomic plugin update',
    () async {
      final root = await Directory.systemTemp.createTemp('codex-config-root-');
      addTearDown(() => root.delete(recursive: true));
      final codexHome = Directory('${root.path}/missing/.codex');
      const plugin = CodexPlugin(
        id: 'sample@local',
        name: 'sample',
        marketplaceName: 'local',
        installed: true,
        enabled: false,
      );

      await CodexPluginStore(
        codexHome: codexHome,
      ).setPluginEnabled(plugin, true);

      final config = File('${codexHome.path}/config.toml');
      expect(
        await config.readAsString(),
        '[plugins."sample@local"]\nenabled = true\n',
      );
      expect(
        await codexHome
            .list()
            .where((entry) => entry.path.contains('.tmp-'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test('preserves a symlinked Codex config when updating a plugin', () async {
    final root = await Directory.systemTemp.createTemp('codex-config-link-');
    addTearDown(() => root.delete(recursive: true));
    final target = File('${root.path}/managed/config.toml');
    await target.parent.create(recursive: true);
    await target.writeAsString('[plugins."sample@local"]\nenabled = false\n');
    final codexHome = Directory('${root.path}/.codex');
    await codexHome.create();
    final configLink = Link('${codexHome.path}/config.toml');
    await configLink.create(target.path);
    const plugin = CodexPlugin(
      id: 'sample@local',
      name: 'sample',
      marketplaceName: 'local',
      installed: true,
      enabled: false,
    );

    await CodexPluginStore(codexHome: codexHome).setPluginEnabled(plugin, true);

    expect(
      await FileSystemEntity.type(configLink.path, followLinks: false),
      FileSystemEntityType.link,
    );
    expect(await target.readAsString(), contains('enabled = true'));
  });

  testWidgets('opens the local Codex plugin manager', (tester) async {
    final pluginStore = _MemoryCodexPluginStore()
      ..plugins.add(
        const CodexPlugin(
          id: 'sample@local',
          name: 'Sample plugin',
          marketplaceName: 'local',
          installed: true,
          enabled: true,
        ),
      );
    final controller = CodexController(pluginStore: pluginStore);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('plugin-manager-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plugin-manager-dialog')), findsOneWidget);
    expect(find.text('Sample plugin'), findsOneWidget);
  });

  testWidgets('shows plugin progress and restart feedback in the manager', (
    tester,
  ) async {
    const plugin = CodexPlugin(
      id: 'available@local',
      name: 'Available plugin',
      marketplaceName: 'local',
      installed: false,
      enabled: false,
    );
    final pluginStore = _BlockingCodexPluginStore()..plugins.add(plugin);
    final controller = CodexController(pluginStore: pluginStore);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('plugin-manager-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装'));
    await tester.pump();

    expect(find.byKey(const Key('plugin-action-progress')), findsOneWidget);
    expect(find.byKey(const Key('plugin-tile-progress')), findsOneWidget);

    pluginStore.installCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plugin-action-result')), findsOneWidget);
    expect(find.textContaining('重启运行时'), findsWidgets);
  });

  test('caches local session metadata during the refresh interval', () async {
    final directory = await Directory.systemTemp.createTemp('codex-sessions-');
    addTearDown(() => directory.delete(recursive: true));
    final sessionFile = File('${directory.path}/rollout.jsonl');
    await sessionFile.writeAsString(
      '${jsonEncode({
        'type': 'session_meta',
        'payload': {'session_id': 'cached-thread', 'timestamp': '2026-08-20T00:00:00.000Z', 'cwd': '/workspace'},
      })}\n',
    );
    final store = LocalSessionThreadStore(directory: directory);

    expect((await store.listThreads('/workspace')).single.id, 'cached-thread');
    await sessionFile.delete();

    expect((await store.listThreads('/workspace')).single.id, 'cached-thread');
  });

  test('serializes consecutive local history writes', () async {
    final store = _BlockingConversationHistoryStore();
    final controller =
        CodexController(
            server: CodexAppServer(),
            conversationHistoryStore: store,
          )
          ..workspacePath = '/workspace'
          ..threads = [_thread(id: 'first-thread')];

    final firstSave = controller.saveConversationHistoryForTesting();
    await store.firstSaveStarted.future;
    controller.threads = [_thread(id: 'second-thread')];
    final secondSave = controller.saveConversationHistoryForTesting();

    expect(store.saveCalls, 1);
    store.allowFirstSave.complete();
    await Future.wait([firstSave, secondSave]);

    expect(store.snapshots['/workspace']!.threads.single.id, 'second-thread');
    controller.dispose();
  });

  test('ignores malformed collection fields in cached history snapshots', () {
    final snapshot = ConversationHistorySnapshot.fromJson({
      'threads': 'invalid',
      'archivedThreads': 42,
      'entries': null,
      'fileChanges': {'invalid': true},
      'pinnedThreadIds': [null, '', 'kept-thread'],
      'turnDiff': 123,
    });

    expect(snapshot.threads, isEmpty);
    expect(snapshot.archivedThreads, isEmpty);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.fileChanges, isEmpty);
    expect(snapshot.pinnedThreadIds, {'kept-thread'});
    expect(snapshot.turnDiff, '123');
  });

  test('rejects unsupported portable history schemas', () {
    expect(
      () => PortableConversationHistory.fromJson({
        'format': 'codex-desk-history',
        'version': 999,
        'snapshot': <String, Object?>{},
      }),
      throwsFormatException,
    );
  });

  test('updates visible account state from App Server notifications', () {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'account/updated',
        params: {'authMode': 'chatgpt', 'planType': 'plus'},
      ),
    );

    expect(controller.authStatus, AuthStatus.chatgpt);
    expect(controller.authLabel, 'ChatGPT plus');
    controller.dispose();
  });

  test('records App Server file changes and unified diffs for display', () {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'lib/main.dart',
                'kind': 'modified',
                'diff': '@@ -1 +1 @@\n-old\n+new',
              },
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': 'diff --git a/lib/main.dart b/lib/main.dart'},
      ),
    );

    expect(controller.fileChanges, [
      const CodexFileChange(
        path: 'lib/main.dart',
        kind: 'modified',
        diff: '@@ -1 +1 @@\n-old\n+new',
      ),
    ]);
    expect(controller.turnDiff, 'diff --git a/lib/main.dart b/lib/main.dart');
    expect(
      controller.entries.map((entry) => '${entry.title}:${entry.detail}'),
      isNot(contains('文件变更:modified lib/main.dart')),
    );
    controller.dispose();
  });

  testWidgets('hides legacy per-file change records from the conversation', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '文件变更',
        detail: '{type: update} lib/main.dart',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '变更已完成。',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.text('文件变更'), findsNothing);
    expect(find.text('{type: update} lib/main.dart'), findsNothing);
    expect(find.text('变更已完成。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hides legacy file change records following a command activity', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'dart format',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '文件变更',
        detail: '{type: update} lib/main.dart',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.text('已运行了命令'), findsOneWidget);
    expect(find.text('已运行 dart format'), findsNothing);
    expect(find.text('文件变更'), findsNothing);
    expect(find.text('{type: update} lib/main.dart'), findsNothing);

    await tester.tap(find.text('已运行了命令'));
    await tester.pump();

    expect(find.text('已运行 dart format'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens the code review surface from the completed file summary', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'lib/main.dart',
                'kind': 'modified',
                'diff': '@@ -1 +1 @@\n-old\n+new',
              },
            ],
          },
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('file-change-summary-card')), findsOneWidget);
    final title = tester.widget<Text>(
      find.byKey(const Key('file-change-summary-title')),
    );
    final stats = tester.widget<Text>(
      find.byKey(const Key('file-change-summary-stats')),
    );
    expect(title.style?.fontSize, 14);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(stats.style?.fontSize, 13);
    await tester.ensureVisible(
      find.byKey(const Key('review-file-changes-button')),
    );
    await tester.tap(find.byKey(const Key('review-file-changes-button')));
    await tester.pump();

    expect(find.byKey(const Key('code-review-dialog')), findsOneWidget);
    expect(find.text('审查'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsWidgets);
    expect(find.byType(SelectableText), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('previews an edited file when the pointer hovers its row', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {'path': 'lib/main.dart', 'kind': 'modified', 'diff': ''},
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': '@@ -432 +432 @@\n-old\n+new'},
      ),
    );
    await tester.pump();

    final row = find.byKey(const ValueKey('file-change-row-lib/main.dart'));
    await tester.ensureVisible(row);
    final rowMouseRegion = tester.widget<MouseRegion>(row);
    rowMouseRegion.onEnter?.call(const PointerEnterEvent());
    await tester.pump();

    expect(find.byKey(const Key('file-change-hover-preview')), findsNothing);
    await tester.pump(codexHoverPopupDelay - const Duration(milliseconds: 1));
    expect(find.byKey(const Key('file-change-hover-preview')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const Key('file-change-hover-preview')), findsOneWidget);
    expect(find.text('lib/main.dart'), findsWidgets);
    expect(find.textContaining('432  -old'), findsOneWidget);
    expect(find.textContaining('+new'), findsOneWidget);
    final previewRect = tester.getRect(
      find.byKey(const Key('file-change-hover-preview')),
    );
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(previewRect.left, greaterThanOrEqualTo(0));
    expect(previewRect.top, greaterThanOrEqualTo(0));
    expect(previewRect.right, lessThanOrEqualTo(viewport.width));
    expect(previewRect.bottom, lessThanOrEqualTo(viewport.height));

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': '@@ -432 +432 @@\n-old\n+updated'},
      ),
    );
    await tester.pump();
    expect(controller.fileChanges.single.diff, isEmpty);
    await tester.pump();
    expect(find.textContaining('+updated'), findsOneWidget);
    expect(find.textContaining('+new'), findsNothing);

    rowMouseRegion.onExit?.call(const PointerExitEvent());
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.byKey(const Key('file-change-hover-preview')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'hydrates a missing file Diff from the read-only Git workspace',
    () async {
      final git = _FakeGitProjectService()
        ..status = const GitProjectStatus(
          isRepository: true,
          changes: [GitProjectChange(code: '??', path: 'hello.py')],
        )
        ..diff = 'diff --git a/hello.py b/hello.py\n+Hello, world!';
      final controller =
          CodexController(server: CodexAppServer(), gitProjectService: git)
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {
              'type': 'fileChange',
              'changes': [
                {'path': '/workspace/hello.py', 'kind': 'added'},
              ],
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.fileChanges.single.diff, contains('+Hello, world!'));
      expect(git.requestedChange?.isUntracked, isTrue);
      controller.dispose();
    },
  );

  testWidgets('keeps aggregate Diff out of the reviewed file count', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {'path': 'hello.py', 'kind': 'added'},
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': '@@ -0 +1 @@\n+Hello, world!'},
      ),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('review-file-changes-button')),
    );
    await tester.tap(find.byKey(const Key('review-file-changes-button')));
    await tester.pump();

    expect(find.text('1 个文件'), findsOneWidget);
    expect(find.text('本次任务完整 Diff'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders the right inspector as a Codex environment card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {'path': 'lib/main.dart', 'kind': 'modified', 'diff': '+card'},
            ],
          },
        },
      ),
    );
    await tester.pump();

    final card = tester.widget<Container>(
      find.byKey(const Key('codex-environment-card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    final cardFinder = find.byKey(const Key('codex-environment-card'));

    expect(find.text('环境信息'), findsOneWidget);
    expect(
      find.descendant(of: cardFinder, matching: find.text('变更')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('本地')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('提交或推送')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('任务文件')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('1 个')),
      findsNWidgets(2),
    );
    final environmentTitle = tester.widget<Text>(find.text('环境信息'));
    final changeLabel = tester.widget<Text>(
      find.descendant(of: cardFinder, matching: find.text('变更')),
    );
    final taskFilesLabel = tester.widget<Text>(
      find.descendant(of: cardFinder, matching: find.text('任务文件')),
    );
    expect(environmentTitle.style?.fontSize, 18);
    expect(changeLabel.style?.fontSize, 14);
    expect(taskFilesLabel.style?.fontSize, 14);
    expect(decoration.borderRadius, BorderRadius.circular(28));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resizes the side panes through their drag handles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final sidebar = find.byKey(const Key('sidebar-pane'));
    final environmentCard = find.byKey(const Key('codex-environment-card'));
    final initialSidebarWidth = tester.getSize(sidebar).width;
    final initialInspectorWidth = tester.getSize(environmentCard).width;

    await tester.drag(
      find.byKey(const Key('sidebar-resize-handle')),
      const Offset(72, 0),
    );
    await tester.pump();
    expect(tester.getSize(sidebar).width, greaterThan(initialSidebarWidth));

    await tester.drag(
      find.byKey(const Key('inspector-resize-handle')),
      const Offset(-72, 0),
    );
    await tester.pump();
    expect(
      tester.getSize(environmentCard).width,
      greaterThan(initialInspectorWidth),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('uses the authentication requirement resolved from Codex config', () {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..authStatus = AuthStatus.signedOut;

    controller.requiresOpenaiAuth = false;
    expect(controller.canSend, isTrue);

    controller.requiresOpenaiAuth = true;
    expect(controller.canSend, isFalse);
    controller.dispose();
  });

  test('disables sending until a restored thread is attached', () async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'restored-thread';

    expect(controller.canSend, isFalse);

    await controller.resumeThread(_thread(id: 'restored-thread'));

    expect(controller.canSend, isTrue);
    controller.dispose();
  });

  test('keeps the connected runtime usable after a failed turn', () {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {
            'status': 'failed',
            'error': {'message': 'request rejected'},
          },
        },
      ),
    );

    expect(controller.status, RuntimeStatus.ready);
    expect(controller.lastError, 'request rejected');
    expect(controller.canSend, isTrue);
    controller.dispose();
  });

  test('marks a completed thread for the sidebar status indicator', () {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'completed-thread'
      ..threads = [_thread(id: 'completed-thread')];

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );

    expect(controller.status, RuntimeStatus.ready);
    expect(controller.threads.single.status, 'idle');
    expect(
      controller.isCompletedThreadAcknowledged('completed-thread'),
      isTrue,
    );
    controller.dispose();
  });

  testWidgets(
    'does not show a completion reminder for the task currently open',
    (tester) async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..activeThreadId = 'current-thread'
        ..threads = [_thread(id: 'current-thread', status: 'idle')];

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(
        find.byKey(const Key('sidebar-completed-task-indicator')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'starts a new task while the previous task runs in the background',
    () async {
      final server = _FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread'
        ..threads = [_thread(id: 'background-thread')];

      expect(controller.canCreateThread, isTrue);
      controller.createThread();

      expect(controller.activeThreadId, isNull);
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.isThreadRunning('background-thread'), isTrue);
      expect(controller.canSend, isTrue);

      expect(await controller.sendPrompt('开始另一个任务'), isTrue);
      expect(controller.activeThreadId, 'new-thread');
      expect(controller.status, RuntimeStatus.running);
      expect(controller.isThreadRunning('background-thread'), isTrue);
      expect(controller.isThreadRunning('new-thread'), isTrue);

      controller.threads = [
        _thread(id: 'background-thread', status: 'active'),
        _thread(id: 'new-thread', status: 'active'),
      ];
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'background-thread',
            'turn': {'status': 'completed'},
          },
        ),
      );

      expect(controller.activeThreadId, 'new-thread');
      expect(controller.status, RuntimeStatus.running);
      expect(controller.isThreadRunning('background-thread'), isFalse);
      expect(controller.isThreadRunning('new-thread'), isTrue);
      expect(
        controller.threads
            .firstWhere((thread) => thread.id == 'background-thread')
            .status,
        'idle',
      );
      controller.dispose();
    },
  );

  test(
    'opens another task while the current task continues in the background',
    () async {
      final server = _FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'running-thread'
        ..threads = [
          _thread(id: 'running-thread', status: 'active'),
          _thread(id: 'next-thread'),
        ];

      await controller.resumeThread(_thread(id: 'next-thread'));

      expect(server.resumedThreadId, 'next-thread');
      expect(controller.activeThreadId, 'next-thread');
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.isThreadRunning('running-thread'), isTrue);
      expect(controller.canSend, isTrue);
      controller.dispose();
    },
  );

  test(
    'opens a running background task without requesting a second writer',
    () async {
      final server = _FakeCodexAppServer()
        ..turnPage = {
          'data': [
            {'id': 'background-turn', 'startedAt': 1, 'items': <JsonMap>[]},
          ],
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread'
        ..activeTurnId = 'background-turn';

      controller.createThread();
      await controller.resumeThread(_thread(id: 'background-thread'));

      expect(server.resumedThreadId, isNull);
      expect(server.turnPageCursors, [isNull]);
      expect(controller.activeThreadId, 'background-thread');
      expect(controller.activeTurnId, 'background-turn');
      expect(controller.status, RuntimeStatus.running);
      expect(controller.canSteer, isTrue);

      expect(await controller.steerCurrentTurn('继续，但换一个方向'), isTrue);
      expect(server.steeredTurnThreadId, 'background-thread');
      expect(server.steeredTurnId, 'background-turn');
      controller.dispose();
    },
  );

  test(
    'keeps the running task active when opening another task fails',
    () async {
      final server = _FakeCodexAppServer()..resumeError = StateError('offline');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'running-thread'
        ..activeTurnId = 'running-turn';

      await controller.resumeThread(_thread(id: 'next-thread'));

      expect(controller.activeThreadId, 'running-thread');
      expect(controller.activeTurnId, 'running-turn');
      expect(controller.status, RuntimeStatus.running);
      expect(controller.isThreadRunning('running-thread'), isTrue);
      controller.dispose();
    },
  );

  testWidgets('allows switching sidebar tasks while another task runs', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running-thread'
      ..threads = [
        _thread(id: 'running-thread', status: 'active'),
        _thread(id: 'next-thread'),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(
      find.byKey(const ValueKey('sidebar-thread-tile-next-thread')),
    );
    // The background task keeps its progress indicator animating, so the
    // widget tree intentionally never settles while it is still running.
    await tester.pump();
    await tester.pump();

    expect(controller.activeThreadId, 'next-thread');
    expect(controller.isThreadRunning('running-thread'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens current-workspace search results while a task runs', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'running-thread'
      ..threads = [
        _thread(id: 'running-thread', status: 'active'),
        _thread(id: 'other-thread'),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('task-search-button')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('task-search-result-other-thread')),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.activeThreadId, 'other-thread');
    expect(controller.isThreadRunning('running-thread'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('interrupts the active turn with both protocol identifiers', () async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    expect(controller.canStop, isTrue);
    await controller.stopCurrentTurn();

    expect(server.interruptedThreadId, 'thread-1');
    expect(server.interruptedTurnId, 'turn-1');
    controller.dispose();
  });

  test('does not expose stop before the active turn id is known', () async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1';

    expect(controller.canStop, isFalse);
    await controller.stopCurrentTurn();
    expect(server.interruptedThreadId, isNull);
    controller.dispose();
  });

  test(
    'does not write a delayed stop result into a newly opened task',
    () async {
      final server = _FakeCodexAppServer()
        ..interruptCompleter = Completer<void>();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'stopped-thread'
        ..activeTurnId = 'stopped-turn';

      final stopping = controller.stopCurrentTurn();
      await Future<void>.delayed(Duration.zero);
      controller
        ..activeThreadId = 'new-thread'
        ..activeTurnId = 'new-turn';
      server.interruptCompleter!.complete();
      await stopping;

      expect(
        controller.entries.where((entry) => entry.title == '已请求停止'),
        isEmpty,
      );
      expect(
        controller.entries.where((entry) => entry.title == '停止失败'),
        isEmpty,
      );
      controller.dispose();
    },
  );

  test(
    'treats an identified current-thread completion as current after stale history',
    () {
      final controller = CodexController(server: _FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'running-thread'
        ..activeTurnId = 'stale-turn'
        ..threads = [_thread(id: 'running-thread', status: 'active')];

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'running-thread',
            'turn': {'id': 'actual-turn', 'status': 'completed'},
          },
        ),
      );

      expect(controller.status, RuntimeStatus.ready);
      expect(controller.activeTurnId, isNull);
      expect(controller.isThreadRunning('running-thread'), isFalse);
      controller.dispose();
    },
  );

  test(
    'keeps an in-flight task bound to its original thread after new chat',
    () async {
      final server = _FakeCodexAppServer()
        ..queueListRequests = true
        ..startThreadResponseIds.addAll(['thread-a', 'thread-b']);
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      final firstSend = controller.sendPrompt('任务 A');
      await Future<void>.delayed(Duration.zero);
      expect(server.listRequests, hasLength(1));

      controller.createThread();
      final secondSend = controller.sendPrompt('任务 B');
      await Future<void>.delayed(Duration.zero);
      expect(server.listRequests, hasLength(2));

      server.listRequests[0].complete(const []);
      expect(await firstSend, isTrue);
      expect(controller.activeThreadId, 'thread-b');
      expect(controller.status, RuntimeStatus.running);
      expect(server.startedTurnThreadIds, ['thread-a']);
      expect(
        controller.threads.map((thread) => thread.id),
        containsAll(['thread-a', 'thread-b']),
      );

      server.listRequests[1].complete(const []);
      expect(await secondSend, isTrue);
      expect(server.startedTurnThreadIds, ['thread-a', 'thread-b']);
      controller.dispose();
    },
  );

  test(
    'reconciles an unscoped completion after refreshing background tasks',
    () async {
      final server = _FakeCodexAppServer()..queueListRequests = true;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread';
      controller.createThread();
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'foreground-thread'
        ..activeTurnId = 'foreground-turn';

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );

      expect(server.listRequests, hasLength(1));
      server.listRequests.single.complete([
        {'id': 'background-thread', 'preview': 'background', 'status': 'idle'},
        {
          'id': 'foreground-thread',
          'preview': 'foreground',
          'status': 'active',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeThreadId, 'foreground-thread');
      expect(controller.activeTurnId, 'foreground-turn');
      expect(controller.status, RuntimeStatus.running);
      expect(controller.isThreadRunning('background-thread'), isFalse);
      controller.dispose();
    },
  );

  test(
    'does not write an unscoped background completion into a new task',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {
            'id': 'background-thread',
            'preview': 'background',
            'status': 'idle',
          },
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread';
      controller.createThread();
      controller.replaceTimelineEntriesForTesting(const []);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeThreadId, isNull);
      expect(
        controller.entries.where((entry) => entry.title == '任务完成'),
        isEmpty,
      );
      expect(controller.isThreadRunning('background-thread'), isFalse);
      controller.dispose();
    },
  );

  test(
    'reconciles an unscoped completion when the focused task is terminal',
    () async {
      final server = _FakeCodexAppServer()..queueListRequests = true;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread';
      controller.createThread();
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'foreground-thread'
        ..activeTurnId = 'foreground-turn'
        ..threads = [
          _thread(id: 'background-thread', status: 'active'),
          _thread(id: 'foreground-thread', status: 'active'),
        ];

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'turn': {'status': 'completed'},
          },
        ),
      );

      expect(server.listRequests, hasLength(1));
      server.listRequests.single.complete([
        {
          'id': 'background-thread',
          'preview': 'background',
          'status': 'active',
        },
        {'id': 'foreground-thread', 'preview': 'foreground', 'status': 'idle'},
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, RuntimeStatus.ready);
      expect(controller.activeTurnId, isNull);
      expect(controller.isThreadRunning('foreground-thread'), isFalse);
      expect(
        controller.threads
            .firstWhere((thread) => thread.id == 'foreground-thread')
            .status,
        'idle',
      );
      controller.dispose();
    },
  );

  testWidgets(
    'keeps user bubbles right aligned with left-aligned wrapped text',
    (tester) async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace';
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: '修复',
          createdAt: DateTime(2026),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final message = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('timeline-user-message')),
          matching: find.text('修复'),
        ),
      );
      expect(message.textAlign, isNull);
      final bubble = tester.getRect(
        find.byKey(const Key('timeline-user-message')),
      );
      expect(bubble.right, closeTo(776, 1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('fades long sidebar task titles instead of showing an ellipsis', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const title = '这是一个很长很长很长很长很长的任务标题，用于验证侧栏渐隐效果';
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..threads = [
        const CodexThread(
          id: 'long-title-thread',
          preview: title,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(
      find.byKey(const ValueKey('sidebar-thread-title-fade-long-title-thread')),
      findsOneWidget,
    );
    final titleText = tester.widget<Text>(find.text(title));
    expect(titleText.overflow, TextOverflow.clip);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('anchors the sidebar title fade to the task row trailing edge', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..threads = [_thread(id: 'short-title')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final taskTile = find.byKey(
      const ValueKey('sidebar-thread-tile-short-title'),
    );
    final fade = find.byKey(
      const ValueKey('sidebar-thread-title-fade-short-title'),
    );
    expect(
      tester.getRect(fade).right,
      closeTo(tester.getRect(taskTile).right - 8, 0.1),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'labels an approval from a background task without writing it to the foreground timeline',
    () {
      final controller = CodexController(server: _FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'background-thread'
        ..threads = [_thread(id: 'background-thread')];
      controller.createThread();
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'foreground-thread';

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/commandExecution/requestApproval',
          requestId: 'background-approval',
          params: {'threadId': 'background-thread', 'command': 'dart test'},
        ),
      );

      expect(controller.pendingApproval?.requestId, 'background-approval');
      expect(controller.pendingApprovalTaskLabel, 'preview-background-thread');
      expect(
        controller.entries.map((entry) => entry.kind),
        isNot(contains(TimelineKind.approval)),
      );
      controller.dispose();
    },
  );

  test('deduplicates concurrent runtime startup attempts', () async {
    final controller = CodexController(
      server: CodexAppServer(executable: '/not/a/codex'),
    )..workspacePath = Directory.systemTemp.path;

    final firstStart = controller.startRuntime();
    final secondStart = controller.startRuntime();

    expect(controller.status, RuntimeStatus.starting);
    await Future.wait([firstStart, secondStart]);

    expect(
      controller.entries.where((entry) => entry.title == '正在启动本地运行时'),
      hasLength(1),
    );
    controller.dispose();
  });

  test('reports a clear diagnostic for a missing Codex executable', () async {
    final server = CodexAppServer(executable: '/not/a/codex');

    final probe = await server.probe();

    expect(probe.isAvailable, isFalse);
    expect(probe.error, contains('未找到 Codex CLI'));
    await server.dispose();
  });

  test(
    'keeps missing CLI failures recoverable with redacted diagnostics on retry',
    () async {
      final controller = CodexController(
        server: CodexAppServer(executable: '/not/a/codex?token=private-token'),
      )..workspacePath = Directory.systemTemp.path;

      await controller.startRuntime();

      expect(controller.status, RuntimeStatus.failed);
      expect(controller.lastError, contains('未找到 Codex CLI'));
      final firstReport = controller.buildRuntimeDiagnosticReport();
      expect(firstReport, contains('Runtime status: failed'));
      expect(firstReport, contains('CLI available: no'));
      expect(firstReport, isNot(contains('private-token')));

      await controller.startRuntime();

      expect(controller.status, RuntimeStatus.failed);
      expect(
        controller.entries.where((entry) => entry.title == '无法启动运行时'),
        hasLength(2),
      );
      controller.dispose();
    },
  );

  test(
    'reads an untracked file and diff from a real temporary Git repository',
    () async {
      final directory = await Directory.systemTemp.createTemp('codex-git-');
      addTearDown(() => directory.delete(recursive: true));
      final initialized = await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: directory.path);
      expect(initialized.exitCode, 0);
      await File(
        '${directory.path}/new_file.txt',
      ).writeAsString('new content\n');
      final service = GitProjectService();

      final configured = await Process.run('git', [
        'config',
        'status.showUntrackedFiles',
        'no',
      ], workingDirectory: directory.path);
      expect(configured.exitCode, 0);

      final status = await service.inspect(directory.path);

      expect(status.isRepository, isTrue);
      final change = status.changes.singleWhere(
        (candidate) => candidate.path == 'new_file.txt',
      );
      expect(change.isUntracked, isTrue);
      final diff = await service.readDiff(
        workspace: directory.path,
        change: change,
      );
      expect(diff, contains('+new content'));

      await service.revertFile(workspace: directory.path, change: change);
      expect(await File('${directory.path}/new_file.txt').exists(), isFalse);
    },
  );

  test('retains Git operation failures for the interface to display', () async {
    final git = _FakeGitProjectService()
      ..stageError = StateError('staging is blocked');
    final controller = CodexController(
      server: CodexAppServer(),
      gitProjectService: git,
    )..workspacePath = '/workspace';

    final succeeded = await controller.stageGitChange(
      const GitProjectChange(code: ' M', path: 'lib/main.dart'),
    );

    expect(succeeded, isFalse);
    expect(controller.gitOperationError, 'staging is blocked');
    controller.dispose();
  });

  test('filters Git changes by state and case-insensitive path query', () {
    const status = GitProjectStatus(
      isRepository: true,
      changes: [
        GitProjectChange(code: 'M ', path: 'lib/staged.dart'),
        GitProjectChange(code: ' M', path: 'lib/Editor.dart'),
        GitProjectChange(code: '??', path: 'notes/TODO.md'),
        GitProjectChange(
          code: 'R ',
          path: 'lib/new_name.dart',
          previousPath: 'lib/Legacy.dart',
        ),
      ],
    );

    expect(
      status.filteredChanges(filter: GitChangeFilter.staged),
      hasLength(2),
    );
    expect(
      status.filteredChanges(filter: GitChangeFilter.untracked).single.path,
      'notes/TODO.md',
    );
    expect(
      status.filteredChanges(query: 'EDITOR').single.path,
      'lib/Editor.dart',
    );
    expect(
      status.filteredChanges(query: 'legacy').single.path,
      'lib/new_name.dart',
    );
  });

  test('marks oversized Git diffs as truncated previews', () async {
    final directory = await Directory.systemTemp.createTemp('codex-git-large-');
    addTearDown(() => directory.delete(recursive: true));
    expect(
      (await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: directory.path)).exitCode,
      0,
    );
    await File('${directory.path}/large.txt').writeAsString(
      List.filled(GitProjectService.maximumDiffCharacters + 1, 'x').join(),
    );
    const change = GitProjectChange(code: '??', path: 'large.txt');

    final preview = await GitProjectService().readDiffPreview(
      workspace: directory.path,
      change: change,
    );

    expect(preview.truncated, isTrue);
    expect(preview.content, endsWith(GitProjectService.truncatedDiffMarker));
  });

  test(
    'loads only read-only Git status and selected diff through controller',
    () async {
      const change = GitProjectChange(code: ' M', path: 'lib/main.dart');
      final git = _FakeGitProjectService()
        ..status = const GitProjectStatus(
          isRepository: true,
          branch: 'main',
          changes: [change],
        )
        ..diff =
            'diff --git a/lib/main.dart b/lib/main.dart\n+@@ -1 +1 @@\n-old\n+new';
      final controller = CodexController(
        server: CodexAppServer(),
        gitProjectService: git,
      )..workspacePath = '/workspace';

      await controller.refreshGitProject();
      await controller.showGitDiff(change);

      expect(git.inspectCalls, 1);
      expect(controller.gitProjectStatus!.branch, 'main');
      expect(git.requestedChange, change);
      expect(controller.gitDiff, contains('+new'));
      controller.dispose();
    },
  );

  testWidgets('opens the Git project workflow view', (tester) async {
    const change = GitProjectChange(code: '??', path: 'new_file.txt');
    final git = _FakeGitProjectService()
      ..status = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: [
          change,
          GitProjectChange(code: ' M', path: 'lib/editor.dart'),
        ],
      )
      ..diff = 'preview\n\n${GitProjectService.truncatedDiffMarker}';
    final controller = CodexController(
      server: CodexAppServer(),
      gitProjectService: git,
    )..workspacePath = '/workspace';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.text('Git 项目'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('git-project-dialog')), findsOneWidget);
    expect(find.text('分支：main'), findsOneWidget);
    expect(find.text('选择文件可查看 Diff、暂存或还原；提交、推送和创建 PR 均需显式确认。'), findsOneWidget);
    expect(find.byKey(const Key('git-change-search')), findsOneWidget);
    expect(find.byKey(const Key('git-change-filter')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('git-change-search')),
      'editor',
    );
    await tester.pump();

    expect(find.text('lib/editor.dart'), findsOneWidget);
    expect(find.text('new_file.txt'), findsNothing);

    await tester.enterText(find.byKey(const Key('git-change-search')), '');
    await tester.pump();
    await tester.tap(find.text('new_file.txt'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('git-diff-truncated-warning')), findsOneWidget);
  });

  test('redacts credentials from runtime diagnostics', () {
    final value = CodexAppServer.redactDiagnosticText(
      'api_key=private-key token: token-value '
      '{"secret":"json-secret"} authorization: Bearer bearer-value '
      'Authorization: Basic YWxpY2U6c2VjcmV0 sk-private',
    );

    expect(value, contains('api_key=***'));
    expect(value, contains('token: ***'));
    expect(value, isNot(contains('private-key')));
    expect(value, isNot(contains('token-value')));
    expect(value, isNot(contains('json-secret')));
    expect(value, isNot(contains('bearer-value')));
    expect(value, contains('Authorization: ***'));
    expect(value, isNot(contains('YWxpY2U6c2VjcmV0')));
    expect(value, isNot(contains('sk-private')));
  });

  test('keeps bounded redacted runtime logs in diagnostic reports', () {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..runtimeProbe = const CodexRuntimeProbe(
        isAvailable: true,
        executablePath: '/usr/local/bin/codex',
        version: 'codex 1.2.3',
        discovery: '自动查找：用户设置、常见安装位置和 PATH。',
      )
      ..lastError = 'token=last-error-token';

    for (var index = 0; index < 201; index++) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'runtime/stderr',
          params: {'message': 'log-$index api_key=secret-$index'},
        ),
      );
    }
    final report = controller.buildRuntimeDiagnosticReport();

    expect(controller.runtimeLogs, hasLength(200));
    expect(controller.runtimeLogs.first.message, contains('log-1'));
    expect(report, contains('CLI version: codex 1.2.3'));
    expect(report, contains('Recent runtime logs (200/200)'));
    expect(report, isNot(contains('secret-')));
    expect(report, isNot(contains('last-error-token')));
    controller.dispose();
  });

  test('preserves the historical provider when resuming a thread', () async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.resumeThread(
      _thread(id: 'openai-thread', modelProvider: 'openai', model: 'gpt-5'),
    );

    expect(server.resumedThreadId, 'openai-thread');
    expect(server.resumedModelProvider, 'openai');
    expect(server.resumedModel, 'gpt-5');
    expect(server.resumedConfig, isNull);
    controller.dispose();
  });

  test('passes every workspace root only when creating a new thread', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-thread-roots-',
    );
    addTearDown(() => root.delete(recursive: true));
    final primary = await Directory(
      '${root.path}/primary',
    ).create(recursive: true);
    final additional = await Directory(
      '${root.path}/additional',
    ).create(recursive: true);
    final server = _FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    await controller.selectWorkspace(primary.path);
    await controller.addWorkspaceRoot(additional.path);
    controller.status = RuntimeStatus.ready;

    await controller.sendPrompt('读取两个目录');

    expect(server.startedThreadDirectory, await primary.resolveSymbolicLinks());
    expect(server.startedRuntimeWorkspaceRoots, [
      await primary.resolveSymbolicLinks(),
      await additional.resolveSymbolicLinks(),
    ]);

    controller
      ..status = RuntimeStatus.ready
      ..activeThreadId = null;
    await controller.resumeThread(_thread(id: 'historical-thread'));
    expect(server.resumedThreadId, 'historical-thread');
    controller.dispose();
  });

  test('encodes runtime workspace roots in the thread start request', () async {
    final server = _ProtocolCaptureCodexAppServer();
    final threadId = await server.startThread(
      workingDirectory: '/primary',
      runtimeWorkspaceRoots: const ['/primary', '/shared'],
    );

    expect(server.requestedMethod, 'thread/start');
    expect(server.requestedParams, {
      'cwd': '/primary',
      'runtimeWorkspaceRoots': ['/primary', '/shared'],
    });
    expect(threadId, 'thread-with-roots');
  });

  test('encodes composer context in the turn start request', () async {
    final server = _ProtocolCaptureCodexAppServer();

    await server.startTurn(
      threadId: 'thread-1',
      prompt: r'$documents Review this image',
      workingDirectory: '/workspace',
      additionalInput: const [
        {'type': 'localImage', 'path': '/tmp/design.png'},
        {
          'type': 'skill',
          'name': 'documents',
          'path': '/skills/documents/SKILL.md',
        },
      ],
      collaborationMode: const {
        'mode': 'plan',
        'settings': {
          'model': 'gpt-test',
          'reasoning_effort': null,
          'developer_instructions': null,
        },
      },
    );

    expect(server.requestedMethod, 'turn/start');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'cwd': '/workspace',
      'input': [
        {'type': 'text', 'text': r'$documents Review this image'},
        {'type': 'localImage', 'path': '/tmp/design.png'},
        {
          'type': 'skill',
          'name': 'documents',
          'path': '/skills/documents/SKILL.md',
        },
      ],
      'collaborationMode': {
        'mode': 'plan',
        'settings': {
          'model': 'gpt-test',
          'reasoning_effort': null,
          'developer_instructions': null,
        },
      },
    });
  });

  test('encodes active-turn direction adjustments', () async {
    final server = _ProtocolCaptureCodexAppServer();

    await server.steerTurn(
      threadId: 'thread-1',
      expectedTurnId: 'turn-1',
      prompt: '改成灰色',
      additionalInput: const [
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ],
    );

    expect(server.requestedMethod, 'turn/steer');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'expectedTurnId': 'turn-1',
      'input': [
        {'type': 'text', 'text': '改成灰色'},
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ],
    });
  });

  test('encodes both thread and turn IDs when interrupting a turn', () async {
    final server = _ProtocolCaptureCodexAppServer();

    await server.interruptTurn(threadId: 'thread-1', turnId: 'turn-1');

    expect(server.requestedMethod, 'turn/interrupt');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'turnId': 'turn-1',
    });
  });

  test('opts into experimental App Server fields during initialize', () async {
    final server = _ProtocolCaptureCodexAppServer();

    await server.initialize();

    expect(server.requestedMethod, 'initialize');
    expect(server.requestedParams, {
      'clientInfo': {
        'name': 'chatgpt_flutter',
        'title': 'Codex Desk',
        'version': '0.1.0',
      },
      'capabilities': {'experimentalApi': true},
    });
    expect(server.notifications, ['initialized']);
  });

  test('applies selected model and effort only to new threads', () async {
    final store = _FakeRuntimeConfigurationStore();
    final server = _FakeCodexAppServer()
      ..modelListResponse = [
        {
          'id': 'gpt-5',
          'model': 'gpt-5',
          'isDefault': true,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'low'},
            {'reasoningEffort': 'high'},
          ],
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: store,
    );
    await controller.waitForInitialConfiguration();
    await controller.refreshReasoningEffortCapabilitiesForTesting();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.setModel('gpt-5');
    await controller.setReasoningEffort(ReasoningEffort.high);
    await controller.sendPrompt('开始新任务');

    expect(store.savedModel, 'gpt-5');
    expect(store.savedReasoningEffort, 'high');
    expect(server.startedModelProvider, isNull);
    expect(server.startedModel, 'gpt-5');
    expect(server.startedConfig, {'model_reasoning_effort': 'high'});

    controller
      ..activeThreadId = null
      ..status = RuntimeStatus.ready;
    await controller.resumeThread(
      _thread(id: 'openai-thread', model: 'historical-model'),
    );

    expect(server.resumedModel, 'historical-model');
    expect(server.resumedConfig, isNull);
    controller.dispose();
  });

  test(
    'switching the new-task model updates supported reasoning strengths',
    () async {
      final store = _FakeRuntimeConfigurationStore();
      final server = _FakeCodexAppServer()
        ..modelListResponse = [
          {
            'id': 'deep-model',
            'model': 'deep-model',
            'displayName': 'Deep model',
            'isDefault': true,
            'supportedReasoningEfforts': [
              {'reasoningEffort': 'high'},
            ],
          },
          {
            'id': 'fast-model',
            'model': 'fast-model',
            'displayName': 'Fast model',
            'isDefault': false,
            'supportedReasoningEfforts': [
              {'reasoningEffort': 'low'},
            ],
          },
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: store,
      );

      await controller.waitForInitialConfiguration();
      await controller.refreshReasoningEffortCapabilitiesForTesting();
      await controller.setReasoningEffort(ReasoningEffort.high);
      await controller.setModel('fast-model');

      expect(controller.selectedModelId, 'fast-model');
      expect(controller.selectedModelLabel, 'Fast model');
      expect(store.savedModel, 'fast-model');
      expect(controller.reasoningEffort, ReasoningEffort.defaultValue);
      expect(controller.reasoningEffortOptions, [
        ReasoningEffort.defaultValue,
        ReasoningEffort.low,
      ]);
      expect(store.savedReasoningEffort, isNull);

      await controller.setModel(null);

      expect(controller.selectedModelId, isNull);
      expect(store.savedModel, isNull);
      expect(controller.reasoningEffortOptions, [
        ReasoningEffort.defaultValue,
        ReasoningEffort.high,
      ]);
      controller.dispose();
    },
  );

  test(
    'only exposes reasoning strengths supported by the default model',
    () async {
      final store = _FakeRuntimeConfigurationStore()..reasoningEffort = 'high';
      final server = _FakeCodexAppServer()
        ..modelListResponse = [
          {
            'id': 'gpt-5',
            'model': 'gpt-5',
            'isDefault': true,
            'supportedReasoningEfforts': [
              {'reasoningEffort': 'low'},
            ],
          },
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: store,
      );

      await controller.waitForInitialConfiguration();
      expect(controller.reasoningEffort, ReasoningEffort.high);
      await controller.refreshReasoningEffortCapabilitiesForTesting();

      expect(controller.reasoningEffort, ReasoningEffort.defaultValue);
      expect(controller.reasoningEffortOptions, [
        ReasoningEffort.defaultValue,
        ReasoningEffort.low,
      ]);
      controller.dispose();
    },
  );

  test('preserves newly advertised reasoning effort values', () async {
    final store = _FakeRuntimeConfigurationStore();
    final server = _FakeCodexAppServer()
      ..modelListResponse = [
        {
          'id': 'future-model',
          'model': 'future-model',
          'isDefault': true,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'ultra'},
          ],
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: store,
    );
    await controller.waitForInitialConfiguration();
    await controller.refreshReasoningEffortCapabilitiesForTesting();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    final ultra = controller.reasoningEffortOptions.singleWhere(
      (effort) => effort.configValue == 'ultra',
    );
    await controller.setReasoningEffort(ultra);
    await controller.sendPrompt('使用新推理强度');

    expect(ultra.label, 'ultra');
    expect(store.savedReasoningEffort, 'ultra');
    expect(server.startedConfig, {'model_reasoning_effort': 'ultra'});
    controller.dispose();
  });

  test(
    'blocks unresolved saved selections when the model catalog fails',
    () async {
      final store = _FakeRuntimeConfigurationStore()
        ..model = 'saved-model'
        ..reasoningEffort = 'high';
      final controller = CodexController(
        server: _FakeCodexAppServer()
          ..modelListError = StateError('catalog unavailable'),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();
      await controller.refreshReasoningEffortCapabilitiesForTesting();
      controller
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      expect(controller.selectedModelLabel, 'saved-model');
      expect(controller.modelSelectionError, contains('catalog unavailable'));
      expect(controller.canSend, isFalse);

      await controller.setModel(null);
      await controller.setReasoningEffort(ReasoningEffort.defaultValue);

      expect(controller.modelSelectionError, isNull);
      expect(controller.canSend, isTrue);
      controller.dispose();
    },
  );

  test(
    'clears runtime-resolved configuration when switching projects',
    () async {
      final firstWorkspace = await Directory.systemTemp.createTemp(
        'codex-config-first-',
      );
      final secondWorkspace = await Directory.systemTemp.createTemp(
        'codex-config-second-',
      );
      addTearDown(() => firstWorkspace.delete(recursive: true));
      addTearDown(() => secondWorkspace.delete(recursive: true));
      final server = _FakeCodexAppServer()
        ..configReadResponse = {
          'config': {
            'model': 'project-model',
            'model_provider': 'project-provider',
          },
          'origins': <String, Object?>{},
        }
        ..modelListResponse = [
          {
            'id': 'project-model',
            'model': 'project-model',
            'isDefault': true,
            'supportedReasoningEfforts': <Object?>[],
          },
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
      )..workspacePath = firstWorkspace.path;
      await controller.refreshCodexConfiguration();
      await controller.refreshReasoningEffortCapabilitiesForTesting();

      expect(controller.configuredModelLabel, 'project-model');
      expect(controller.providerLabel, 'project-provider');
      expect(controller.modelOptions, isNotEmpty);

      await controller.selectWorkspace(secondWorkspace.path);

      expect(controller.codexConfigurationRead, isFalse);
      expect(controller.configuredModelLabel, '等待读取运行时配置');
      expect(controller.providerLabel, 'Codex 配置');
      expect(controller.modelOptions, isEmpty);
      controller.dispose();
    },
  );

  test(
    'loads user, agent, and command history when resuming a thread',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'turn-1',
                'items': [
                  {
                    'id': 'user-item',
                    'type': 'userMessage',
                    'content': [
                      {'type': 'text', 'text': '历史问题'},
                    ],
                  },
                  {'id': 'agent-item', 'type': 'agentMessage', 'text': '历史回答'},
                  {
                    'id': 'command-item',
                    'type': 'commandExecution',
                    'command': 'dart test',
                    'aggregatedOutput': 'All tests passed',
                  },
                  {
                    'id': 'search-item',
                    'type': 'webSearch',
                    'query': 'Codex App Server',
                    'results': [{}, {}],
                  },
                  {
                    'id': 'mcp-item',
                    'type': 'mcpToolCall',
                    'server': 'docs',
                    'tool': 'search',
                    'status': 'completed',
                  },
                ],
              },
            ],
          },
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'history-thread'));

      expect(
        controller.entries.map((entry) => '${entry.title}:${entry.detail}'),
        containsAll([
          '你:历史问题',
          'Codex:历史回答',
          '执行命令:dart test\nAll tests passed',
          '网页搜索:Codex App Server · 2 条结果',
          'MCP 工具：docs/search:completed',
        ]),
      );
      controller.dispose();
    },
  );

  test(
    'marks thread history restoration separately from live output',
    () async {
      final controller = CodexController(server: _FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      final restorationStates = <bool>[];
      controller.addListener(
        () => restorationStates.add(controller.isResumingThread),
      );

      await controller.resumeThread(_thread(id: 'history-thread'));

      expect(restorationStates, contains(true));
      expect(restorationStates.last, isFalse);
      expect(controller.isResumingThread, isFalse);
      controller.dispose();
    },
  );

  test(
    'restores a previously opened task view from the in-memory cache',
    () async {
      final controller = CodexController(server: _FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      final first = _thread(id: 'first-thread');
      final second = _thread(id: 'second-thread');

      await controller.resumeThread(first);
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: 'first cached page',
          createdAt: DateTime(2026),
        ),
      ]);
      await controller.resumeThread(second);
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: 'second page',
          createdAt: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      ]);

      await controller.resumeThread(first);

      expect(controller.entries.single.detail, 'first cached page');
      expect(controller.hasCachedActiveThreadView, isTrue);
      controller.dispose();
    },
  );

  test('retains only the most recently opened task views in memory', () async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    for (var index = 0; index < 9; index++) {
      await controller.resumeThread(_thread(id: 'thread-$index'));
    }

    expect(controller.cachedThreadViewIds, hasLength(8));
    expect(controller.cachedThreadViewIds, isNot(contains('thread-0')));
    expect(controller.cachedThreadViewIds, contains('thread-8'));
    controller.dispose();
  });

  testWidgets(
    'groups consecutive command and tool history into an activity list',
    (tester) async {
      final controller = CodexController(server: CodexAppServer());
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.command,
          title: '执行命令',
          detail: 'flutter analyze\nNo issues found',
          createdAt: DateTime(2026),
        ),
        TimelineEntry(
          kind: TimelineKind.tool,
          title: '网页搜索',
          detail: 'Codex activity lists · 1 条结果',
          createdAt: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(find.text('已运行了命令并进行了搜索'), findsOneWidget);
      expect(find.text('已运行 flutter analyze'), findsNothing);
      expect(find.text('网页搜索'), findsNothing);

      await tester.tap(find.text('已运行了命令并进行了搜索'));
      await tester.pump();

      expect(find.text('已运行 flutter analyze'), findsOneWidget);
      expect(find.text('网页搜索'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('keeps separate activity groups with matching timestamps', (
    tester,
  ) async {
    final timestamp = DateTime(2026);
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'first command',
        createdAt: timestamp,
      ),
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: 'separates activity groups',
        createdAt: timestamp,
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'second command',
        createdAt: timestamp,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final summaries = find.text('已运行了命令');
    expect(summaries, findsNWidgets(2));
    await tester.tap(summaries.first);
    await tester.pump();

    expect(find.text('已运行 first command'), findsOneWidget);
    expect(find.text('已运行 second command'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('restores the previous active thread when resume fails', () async {
    final server = _FakeCodexAppServer()..resumeError = StateError('offline');
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'old-thread';

    await controller.resumeThread(_thread(id: 'new-thread'));

    expect(controller.status, RuntimeStatus.ready);
    expect(controller.activeThreadId, 'old-thread');
    expect(server.resumedThreadId, 'new-thread');
    expect(controller.lastError, 'offline');
    controller.dispose();
  });

  test(
    'keeps the previous timeline clean when a resume writer conflict occurs',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeError = StateError('thread already has an active writer');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..activeThreadId = 'old-thread';
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: '仍在查看旧任务',
          createdAt: DateTime(2026),
        ),
      ]);

      await controller.resumeThread(_thread(id: 'shared-thread'));

      expect(controller.activeThreadId, 'old-thread');
      expect(controller.hasResumeConflict, isTrue);
      expect(
        controller.entries.where((entry) => entry.title == '无法恢复任务'),
        isEmpty,
      );
      expect(controller.entries.single.detail, '仍在查看旧任务');
      controller.dispose();
    },
  );

  testWidgets(
    'shows a non-blocking retry notice when another app owns a thread writer',
    (tester) async {
      final server = _FakeCodexAppServer()
        ..resumeError = StateError('thread already has an active writer');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'shared-thread'));
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(
        find.byKey(const Key('thread-open-elsewhere-notice')),
        findsOneWidget,
      );
      expect(find.text('已在另一个应用中打开'), findsOneWidget);
      expect(find.text('请先在那边关闭会话，然后重试此操作。'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      server.resumeError = null;
      await tester.tap(find.byKey(const Key('thread-open-elsewhere-retry')));
      await tester.pump();
      await tester.pump();

      expect(controller.activeThreadId, 'shared-thread');
      expect(controller.hasResumeConflict, isFalse);
      expect(
        find.byKey(const Key('thread-open-elsewhere-notice')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('requires unarchive before reopening a task archived elsewhere', (
    tester,
  ) async {
    final server = _FakeCodexAppServer()
      ..resumeError = StateError('session archived-thread is archived')
      ..archivedListResponse = [
        {'id': 'archived-thread', 'preview': '已归档任务'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.resumeThread(_thread(id: 'archived-thread'));
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(controller.activeThreadId, isNull);
    expect(
      controller.entries.where((entry) => entry.title == '无法恢复任务'),
      isEmpty,
    );
    expect(find.byKey(const Key('thread-archived-notice')), findsOneWidget);
    expect(find.text('取消归档'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  test(
    'keeps the archived-task restore action after unarchive fails',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeError = StateError('session archived-thread is archived')
        ..unarchiveError = StateError('unarchive unavailable');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'archived-thread'));
      await controller.restoreArchivedThread();

      expect(controller.hasArchivedThreadRestore, isTrue);
      expect(controller.lastError, 'unarchive unavailable');
      controller.dispose();
    },
  );

  test('clears a writer-conflict retry when switching workspaces', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-writer-conflict-switch-',
    );
    addTearDown(() => root.delete(recursive: true));
    final first = await Directory('${root.path}/first').create();
    final second = await Directory('${root.path}/second').create();
    final server = _ManagedRuntimeFakeServer()
      ..resumeError = StateError('thread already has an active writer')
      ..running = true;
    final controller =
        CodexController(
            server: server,
            runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
            conversationHistoryStore: _MemoryConversationHistoryStore(),
          )
          ..workspacePath = first.path
          ..status = RuntimeStatus.ready;

    await controller.resumeThread(_thread(id: 'shared-thread'));
    expect(controller.hasThreadWriterConflict, isTrue);

    expect(await controller.selectWorkspaceAndReconnect(second.path), isTrue);
    expect(controller.workspacePath, await second.resolveSymbolicLinks());
    expect(controller.hasThreadWriterConflict, isFalse);
    await controller.retryThreadWriterConflict();
    expect(server.resumeCalls, 1);
    controller.dispose();
  });

  test(
    'hydrates older turns when resume returns a pagination cursor',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'turnsBackwardsCursor': 'older-cursor',
          'thread': {
            'turns': [
              {
                'id': 'new-turn',
                'startedAt': 2,
                'items': [
                  {'id': 'new-agent', 'type': 'agentMessage', 'text': '新回答'},
                ],
              },
            ],
          },
        }
        ..turnPage = {
          'data': [
            {
              'id': 'old-turn',
              'startedAt': 1,
              'items': [
                {
                  'id': 'old-user',
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': '旧问题'},
                  ],
                },
              ],
            },
          ],
          'nextCursor': null,
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'paginated-thread'));

      expect(server.turnPageCursors, ['older-cursor']);
      final details = controller.entries.map((entry) => entry.detail).toList();
      expect(details.indexOf('旧问题'), lessThan(details.indexOf('新回答')));
      controller.dispose();
    },
  );

  test(
    'hydrates unloaded turn items through thread items pagination',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'summary-turn',
                'itemsView': 'notLoaded',
                'items': <JsonMap>[],
              },
            ],
          },
        }
        ..itemPage = {
          'data': [
            {
              'turnId': 'summary-turn',
              'item': {
                'id': 'hydrated-agent',
                'type': 'agentMessage',
                'text': '按项分页恢复的回答',
              },
            },
          ],
          'nextCursor': null,
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'item-history-thread'));

      expect(server.itemPageTurnIds, ['summary-turn']);
      expect(
        controller.entries.map((entry) => entry.detail),
        contains('按项分页恢复的回答'),
      );
      controller.dispose();
    },
  );

  test(
    'does not show the prior timeline when item history hydration fails',
    () async {
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'unavailable-turn',
                'itemsView': 'notLoaded',
                'items': <JsonMap>[],
              },
            ],
          },
        }
        ..itemPageError = StateError('items unavailable');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..activeThreadId = 'old-thread';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {'itemId': 'old-message', 'delta': '旧线程回答'},
        ),
      );

      await controller.resumeThread(_thread(id: 'target-thread'));

      expect(controller.activeThreadId, 'target-thread');
      expect(server.resumedThreadId, 'target-thread');
      expect(
        controller.entries.map((entry) => entry.detail),
        isNot(contains('旧线程回答')),
      );
      expect(
        controller.entries.map((entry) => entry.title),
        contains('历史内容加载不完整'),
      );
      controller.dispose();
    },
  );

  test(
    'keeps partial item history when a turn exceeds the page limit',
    () async {
      final pages = List<JsonMap>.generate(
        20,
        (index) => {
          'data': [
            {
              'turnId': 'long-turn',
              'item': {
                'id': 'item-$index',
                'type': 'agentMessage',
                'text': '第 $index 项',
              },
            },
          ],
          'nextCursor': 'cursor-$index',
        },
      );
      final server = _FakeCodexAppServer()
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'long-turn',
                'itemsView': 'notLoaded',
                'items': <JsonMap>[],
              },
            ],
          },
        }
        ..itemPages = pages;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      await controller.resumeThread(_thread(id: 'long-history-thread'));

      expect(controller.activeThreadId, 'long-history-thread');
      expect(server.itemPageTurnIds, hasLength(20));
      expect(
        controller.entries.map((entry) => entry.title),
        contains('历史内容未完全加载'),
      );
      controller.dispose();
    },
  );

  test('ignores an older concurrent thread refresh result', () async {
    final server = _FakeCodexAppServer()..queueListRequests = true;
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace';

    final first = controller.refreshThreads();
    final second = controller.refreshThreads();
    expect(server.listRequests, hasLength(2));

    server.listRequests[1].complete([
      {'id': 'newer', 'preview': 'newer'},
    ]);
    await second;
    server.listRequests[0].complete([
      {'id': 'older', 'preview': 'older'},
    ]);
    await first;

    expect(controller.threads.single.id, 'newer');
    expect(controller.threadsLoading, isFalse);
    controller.dispose();
  });

  test(
    'keeps task positions stable when a refresh reports a new update order',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {
            'id': 'first',
            'preview': 'first updated most recently',
            'createdAt': 1,
            'updatedAt': 20,
            'status': 'idle',
          },
          {
            'id': 'second',
            'preview': 'second updated earlier',
            'createdAt': 2,
            'updatedAt': 10,
            'status': 'active',
          },
          {
            'id': 'new',
            'preview': 'new task',
            'createdAt': 3,
            'updatedAt': 3,
            'status': 'idle',
          },
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..threads = [_thread(id: 'second'), _thread(id: 'first')];

      await controller.refreshThreads();

      expect(controller.threads.map((thread) => thread.id), [
        'second',
        'first',
        'new',
      ]);
      expect(controller.threads[1].preview, 'first updated most recently');
      controller.dispose();
    },
  );

  test('restores archived threads to the active thread list', () async {
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'restored-thread', 'preview': '已恢复任务'},
      ]
      ..archivedListResponse = [
        {'id': 'restored-thread', 'preview': '已恢复任务'},
      ];
    final controller =
        CodexController(
            server: server,
            localSessionThreadStore: _MemoryLocalSessionThreadStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;

    await controller.refreshArchivedThreads();
    expect(controller.archivedThreads.single.id, 'restored-thread');

    await controller.unarchiveThread(controller.archivedThreads.single);

    expect(server.unarchivedThreadId, 'restored-thread');
    expect(controller.archivedThreads, isEmpty);
    expect(controller.threads.single.id, 'restored-thread');
    controller.dispose();
  });

  test(
    'archives selected tasks in sequence and clears their local pins',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'first', 'preview': 'first'},
          {'id': 'second', 'preview': 'second'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();
      controller.toggleThreadPinned(controller.threads.first);

      await controller.archiveThreads(controller.threads);

      expect(server.archivedThreadIds, ['first', 'second']);
      expect(controller.threads, isEmpty);
      expect(controller.isThreadPinned('first'), isFalse);
      expect(
        controller.entries
            .lastWhere((entry) => entry.title == '任务已批量归档')
            .detail,
        '已归档 2 个任务。',
      );
      controller.dispose();
    },
  );

  testWidgets(
    'blocks archive with the writer-conflict notice and retries the archive',
    (tester) async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'shared-thread', 'preview': 'shared'},
        ]
        ..archiveError = StateError('thread already has an active writer');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();

      await controller.archiveThread(controller.threads.single);
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(controller.hasThreadWriterConflict, isTrue);
      expect(controller.threads.single.id, 'shared-thread');
      expect(
        find.byKey(const Key('thread-open-elsewhere-notice')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        controller.entries.where((entry) => entry.title == '归档失败'),
        isEmpty,
      );

      server.archiveError = null;
      await tester.tap(find.byKey(const Key('thread-open-elsewhere-retry')));
      await tester.pump();
      await tester.pump();

      expect(server.archivedThreadIds, ['shared-thread']);
      expect(controller.hasThreadWriterConflict, isFalse);
      expect(
        find.byKey(const Key('thread-open-elsewhere-notice')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'retries every unarchived task after a batch archive writer conflict',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'first', 'preview': 'first'},
          {'id': 'second', 'preview': 'second'},
          {'id': 'third', 'preview': 'third'},
        ]
        ..archiveErrorsById['second'] = StateError(
          'thread already has an active writer',
        );
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();

      final firstPass = await controller.archiveThreads(controller.threads);

      expect(firstPass, {'first'});
      expect(server.archivedThreadIds, ['first']);
      expect(controller.threads.map((thread) => thread.id), [
        'second',
        'third',
      ]);
      expect(controller.hasThreadWriterConflict, isTrue);

      server.archiveErrorsById.remove('second');
      await controller.retryThreadWriterConflict();

      expect(server.archivedThreadIds, ['first', 'second', 'third']);
      expect(controller.threads, isEmpty);
      expect(server.archiveCalls, 4);
      expect(controller.hasThreadWriterConflict, isFalse);
      controller.dispose();
    },
  );

  test(
    'prevents duplicate archive requests for a task already updating',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'archive-once', 'preview': '只归档一次'},
        ]
        ..archiveCompleter = Completer<void>();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();
      final thread = controller.threads.single;

      final first = controller.archiveThreads([thread]);
      await Future<void>.delayed(Duration.zero);
      final second = await controller.archiveThreads([thread]);

      expect(server.archiveCalls, 1);
      expect(second, isEmpty);
      server.archiveCompleter!.complete();
      expect(await first, {thread.id});
      controller.dispose();
    },
  );

  test(
    'permanently deletes an archived task and removes it from local lists',
    () async {
      final server = _FakeCodexAppServer()
        ..archivedListResponse = [
          {'id': 'remove-me', 'preview': 'remove-me'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshArchivedThreads();

      await controller.deleteThread(controller.archivedThreads.single);

      expect(server.deletedThreadIds, ['remove-me']);
      expect(controller.archivedThreads, isEmpty);
      expect(
        controller.entries
            .lastWhere((entry) => entry.title == '任务已永久删除')
            .detail,
        'remove-me',
      );
      controller.dispose();
    },
  );

  test('does not restore a deleted task from local session fallback', () async {
    final localSessions = _MemoryLocalSessionThreadStore()
      ..threadsByWorkspace['/workspace'] = [_thread(id: 'remove-me')];
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'remove-me', 'preview': 'remove-me'},
      ];
    final controller =
        CodexController(server: server, localSessionThreadStore: localSessions)
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await controller.refreshThreads();

    await controller.deleteThread(controller.threads.single);

    expect(controller.threads, isEmpty);
    controller.dispose();
  });

  test(
    'persists completed batch archive state when a later task fails',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'first', 'preview': 'first'},
          {'id': 'second', 'preview': 'second'},
        ]
        ..archiveFailureIds.add('second');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.refreshThreads();

      final archivedIds = await controller.archiveThreads(controller.threads);

      expect(archivedIds, {'first'});
      expect(controller.threads.single.id, 'second');
      expect(
        controller.entries
            .lastWhere((entry) => entry.title == '部分任务归档失败')
            .detail,
        contains('无法归档 second'),
      );
      controller.dispose();
    },
  );

  test('prevents duplicate archived thread restore requests', () async {
    final server = _FakeCodexAppServer()
      ..archivedListResponse = [
        {'id': 'restore-once', 'preview': '只恢复一次'},
      ]
      ..unarchiveCompleter = Completer<void>();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.refreshArchivedThreads();
    final thread = controller.archivedThreads.single;
    final first = controller.unarchiveThread(thread);
    await Future<void>.delayed(Duration.zero);
    await controller.unarchiveThread(thread);

    expect(server.unarchiveCalls, 1);
    expect(controller.isUnarchivingThread(thread.id), isTrue);
    server.unarchiveCompleter!.complete();
    await first;
    expect(controller.isUnarchivingThread(thread.id), isFalse);
    controller.dispose();
  });

  test('refreshes archived threads after archive notifications', () async {
    final server = _FakeCodexAppServer()
      ..archivedListResponse = [
        {'id': 'archived-now', 'preview': '已归档'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.refreshArchivedThreads();
    server.archivedListResponse = <JsonMap>[];
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/archived',
        params: {'threadId': 'archived-now'},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.archivedThreads, isEmpty);
    controller.dispose();
  });

  test(
    'refreshes both task lists after thread deletion notifications',
    () async {
      final server = _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'deleted', 'preview': 'deleted'},
        ]
        ..archivedListResponse = [
          {'id': 'deleted-archived', 'preview': 'deleted archived'},
        ];
      final controller =
          CodexController(
              server: server,
              localSessionThreadStore: _MemoryLocalSessionThreadStore(),
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;
      await Future.wait([
        controller.refreshThreads(),
        controller.refreshArchivedThreads(),
      ]);
      server
        ..listResponse = <JsonMap>[]
        ..archivedListResponse = <JsonMap>[];

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'thread/deleted',
          params: {'threadId': 'deleted'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.threads, isEmpty);
      expect(controller.archivedThreads, isEmpty);
      controller.dispose();
    },
  );
}
