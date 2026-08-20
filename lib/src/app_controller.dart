import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'domain/codex_thread.dart';
import 'domain/codex_file_change.dart';
import 'domain/pending_approval.dart';
import 'domain/relay_provider_configuration.dart';
import 'domain/timeline_entry.dart';
import 'services/codex_app_server.dart';
import 'services/conversation_history_store.dart';
import 'services/relay_provider_store.dart';
import 'services/runtime_configuration_store.dart';

enum RuntimeStatus { stopped, starting, ready, running, failed }

enum AuthStatus { checking, signedOut, chatgpt, apiKey, external }

enum ApprovalMode { manual, autoApprove }

/// 推理强度会以 Codex 配置键 `model_reasoning_effort` 传递给 App Server；保留 [defaultValue] 则使用模型默认值。
/// The value is passed to App Server as the Codex configuration key `model_reasoning_effort`; [defaultValue] lets the selected model use its own default.
enum ReasoningEffort { defaultValue, minimal, low, medium, high, xhigh }

extension ReasoningEffortLabel on ReasoningEffort {
  /// 返回用于界面的本地化推理强度标签。
  /// Returns the localized reasoning-effort label for the UI.
  String get label => switch (this) {
    ReasoningEffort.defaultValue => '默认',
    ReasoningEffort.minimal => '最小',
    ReasoningEffort.low => '低',
    ReasoningEffort.medium => '中',
    ReasoningEffort.high => '高',
    ReasoningEffort.xhigh => '极高',
  };

  /// 返回要发送给 App Server 的配置值，默认项为 `null`。
  /// Returns the value sent to App Server; the default option is `null`.
  String? get configValue => switch (this) {
    ReasoningEffort.defaultValue => null,
    ReasoningEffort.minimal => 'minimal',
    ReasoningEffort.low => 'low',
    ReasoningEffort.medium => 'medium',
    ReasoningEffort.high => 'high',
    ReasoningEffort.xhigh => 'xhigh',
  };

  /// 将保存或服务器返回的配置值转换为枚举值。
  /// Converts a persisted or server-provided configuration value to the enum.
  static ReasoningEffort fromConfigValue(String? value) => switch (value) {
    'low' => ReasoningEffort.low,
    'minimal' => ReasoningEffort.minimal,
    'medium' => ReasoningEffort.medium,
    'high' => ReasoningEffort.high,
    'xhigh' => ReasoningEffort.xhigh,
    _ => ReasoningEffort.defaultValue,
  };
}

extension ApprovalModeLabel on ApprovalMode {
  /// 返回用于界面的本地化审批模式标签。
  /// Returns the localized approval-mode label for the UI.
  String get label => switch (this) {
    ApprovalMode.manual => '逐次确认',
    ApprovalMode.autoApprove => '自动批准',
  };
}

class CodexController extends ChangeNotifier {
  CodexController({
    CodexAppServer? server,
    RelayProviderStore? relayProviderStore,
    RuntimeConfigurationStore? runtimeConfigurationStore,
    ConversationHistoryStore? conversationHistoryStore,
  }) : _server = server ?? CodexAppServer(),
       _relayProviderStore = relayProviderStore ?? RelayProviderStore(),
       _runtimeConfigurationStore =
           runtimeConfigurationStore ?? RuntimeConfigurationStore(),
       _conversationHistoryStore =
           conversationHistoryStore ??
           testingConversationHistoryStore ??
           ConversationHistoryStore() {
    _entries.add(
      _entry(
        TimelineKind.system,
        '欢迎使用 Codex Desk',
        '选择本地项目后启动 Codex App Server。密钥不会写入项目或日志。',
      ),
    );
    _relayLoad = _loadRelayProvider();
    _runtimeLoad = _loadRuntimeConfiguration();
    _workspaceLoad = _loadWorkspace();
    _historyLoad = _loadConversationHistory();
  }

  final CodexAppServer _server;

  @visibleForTesting
  static ConversationHistoryStore? testingConversationHistoryStore;
  final RelayProviderStore _relayProviderStore;
  final RuntimeConfigurationStore _runtimeConfigurationStore;
  final ConversationHistoryStore _conversationHistoryStore;
  StreamSubscription<ServerEvent>? _eventSubscription;
  final List<TimelineEntry> _entries = [];
  final Map<String, CodexFileChange> _fileChangesByPath = {};
  final Map<String, int> _agentEntryIndexByItem = {};
  Timer? _deltaNotificationTimer;
  Timer? _historySaveTimer;
  Future<void> _historySave = Future.value();
  bool _historySaveFailed = false;
  bool _disposed = false;
  bool _startingRuntime = false;
  int _threadRefreshEpoch = 0;
  int _threadRefreshRequest = 0;
  int _archivedThreadRefreshRequest = 0;
  final Set<String> _unarchivingThreadIds = {};
  Future<void> _reasoningEffortSave = Future.value();
  Map<String, Set<ReasoningEffort>> _reasoningEffortsByModel = const {};
  String? _defaultModelId;
  late final Future<void> _relayLoad;
  late final Future<void> _runtimeLoad;
  late final Future<void> _workspaceLoad;
  late final Future<void> _historyLoad;

  RuntimeStatus status = RuntimeStatus.stopped;
  String? workspacePath;
  String? activeThreadId;
  String? lastError;
  PendingApproval? pendingApproval;
  bool approvalResponding = false;
  ApprovalMode approvalMode = ApprovalMode.manual;
  ReasoningEffort reasoningEffort = ReasoningEffort.defaultValue;
  List<ReasoningEffort> reasoningEffortOptions = const [
    ReasoningEffort.defaultValue,
  ];
  AuthStatus authStatus = AuthStatus.checking;
  String? accountEmail;
  String? accountPlan;
  String? loginUrl;
  bool loginInProgress = false;
  bool requiresOpenaiAuth = false;
  RelayProviderConfiguration? relayProvider;
  bool relayLoading = true;
  bool relaySaving = false;
  String? relayError;
  CodexRuntimeProbe? runtimeProbe;
  String? runtimeError;
  bool runtimeChecking = false;
  List<CodexThread> threads = const [];
  bool threadsLoading = false;
  String? threadsError;
  List<CodexThread> archivedThreads = const [];
  bool archivedThreadsLoading = false;
  String? archivedThreadsError;

  /// 返回不可修改的当前时间线副本视图。
  /// Returns an unmodifiable view of the current timeline.
  List<TimelineEntry> get entries => List.unmodifiable(_entries);

  /// 返回不可修改的已记录文件变更视图。
  /// Returns an unmodifiable view of recorded file changes.
  List<CodexFileChange> get fileChanges =>
      List.unmodifiable(_fileChangesByPath.values);
  String? turnDiff;

  /// 指示当前状态是否允许发送新任务。
  /// Indicates whether the current state permits sending a new task.
  bool get canSend =>
      status == RuntimeStatus.ready &&
      workspacePath != null &&
      (relayProvider != null ||
          !requiresOpenaiAuth ||
          authStatus != AuthStatus.signedOut);

  /// 指示当前正在运行的任务是否可以中断。
  /// Indicates whether the running task can be interrupted.
  bool get canStop => status == RuntimeStatus.running && activeThreadId != null;

  /// 指示当前是否可以安全切换本地项目。
  /// Indicates whether it is safe to switch the local workspace.
  bool get canChooseWorkspace =>
      status == RuntimeStatus.stopped ||
      (status == RuntimeStatus.failed && !_server.isRunning);

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

  /// 返回当前线程使用的 Provider 展示名称。
  /// Returns the display name of the provider used by current threads.
  String get providerLabel => relayProvider == null ? 'OpenAI' : '中转站';

  /// 指示运行时路径是否可以在不影响会话的情况下配置。
  /// Indicates whether the runtime path can be configured without disrupting a session.
  bool get canConfigureRuntime =>
      !_startingRuntime &&
      status != RuntimeStatus.starting &&
      !_server.isRunning;

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
    await _saveConversationHistory();
    _invalidateThreadRefreshes();
    workspacePath = canonicalPath;
    activeThreadId = null;
    threads = const [];
    archivedThreads = const [];
    _clearStreamingState();
    _clearFileChanges();
    _resetConversationTimeline();
    await _restoreConversationHistory(canonicalPath);
    _add(TimelineKind.system, '项目已选择', canonicalPath);
    notifyListeners();
    try {
      await _runtimeConfigurationStore.saveWorkspace(canonicalPath);
    } catch (error) {
      _add(TimelineKind.error, '无法保存项目选择', _messageOf(error));
      if (!_disposed) notifyListeners();
    }
  }

  /// 清空当前任务状态，使下一条消息创建新的服务器线程。
  /// Clears the current task state so the next message creates a server thread.
  void createThread() {
    if (status != RuntimeStatus.ready || workspacePath == null) {
      lastError = '运行时就绪后才能新建任务。';
      notifyListeners();
      return;
    }
    activeThreadId = null;
    _clearStreamingState();
    _clearFileChanges();
    _resetConversationTimeline();
    _add(TimelineKind.system, '已新建任务', '发送第一条消息后会创建新的 Thread。');
    notifyListeners();
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

    _startingRuntime = true;
    _invalidateThreadRefreshes();
    status = RuntimeStatus.starting;
    lastError = null;
    _add(TimelineKind.system, '正在启动本地运行时', 'codex app-server · $workspace');
    notifyListeners();

    try {
      await Future.wait([_relayLoad, _runtimeLoad, _workspaceLoad]);
      final probe = await _inspectRuntime(notify: false);
      if (!probe.isAvailable) {
        throw StateError(probe.error ?? 'Codex CLI 不可用。');
      }
      _eventSubscription ??= _server.events.listen(_handleServerEvent);
      if (_server.isRunning) await _server.stop();
      await _server.start(
        workingDirectory: workspace,
        environment: relayProvider?.processEnvironment,
      );
      await _server.initialize();
      await refreshAccount();
      await _refreshReasoningEffortCapabilities();
      status = RuntimeStatus.ready;
      _add(TimelineKind.system, '运行时已连接', 'App Server 已通过本地 stdio 通道就绪。');
      await refreshThreads();
    } catch (error) {
      status = RuntimeStatus.failed;
      lastError = _messageOf(error);
      _add(TimelineKind.error, '无法启动运行时', lastError!);
    } finally {
      _startingRuntime = false;
    }
    notifyListeners();
  }

  /// 向当前或新建线程发送用户提示词。
  /// Sends a user prompt to the current or a newly created thread.
  Future<void> sendPrompt(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || !canSend) return;
    final workspace = workspacePath!;
    if (activeThreadId == null) {
      _resetConversationTimeline();
      _clearFileChanges();
    }
    status = RuntimeStatus.running;
    lastError = null;
    _clearStreamingState();
    _add(TimelineKind.user, '你', text);
    notifyListeners();

    try {
      activeThreadId ??= await _server.startThread(
        workingDirectory: workspace,
        modelProvider: relayProvider == null
            ? null
            : RelayProviderConfiguration.providerId,
        model: relayProvider?.model,
        config: _threadConfig(
          usesRelay: relayProvider != null,
          model: relayProvider?.model,
          useDefaultModelWhenMissing: relayProvider == null,
        ),
      );
      await refreshThreads();
      final id = activeThreadId!;
      final shortId = id.length > 12 ? id.substring(0, 12) : id;
      _add(TimelineKind.system, '任务已创建', 'Thread $shortId');
      await _server.startTurn(
        threadId: id,
        prompt: text,
        workingDirectory: workspace,
      );
    } catch (error) {
      status = RuntimeStatus.failed;
      lastError = _messageOf(error);
      _add(TimelineKind.error, '任务未能启动', lastError!);
    }
    notifyListeners();
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

  /// 停止 App Server 并重置仅在运行期有效的状态。
  /// Stops App Server and resets state that is only valid while it runs.
  Future<void> stopRuntime() async {
    if (status == RuntimeStatus.stopped && !_server.isRunning) return;
    try {
      await _server.stop();
      _invalidateThreadRefreshes();
      status = RuntimeStatus.stopped;
      activeThreadId = null;
      pendingApproval = null;
      approvalResponding = false;
      _clearStreamingState();
      _add(TimelineKind.system, '运行时已停止', '现在可以切换项目或重新启动运行时。');
    } catch (error) {
      status = RuntimeStatus.failed;
      lastError = _messageOf(error);
      _add(TimelineKind.error, '停止运行时失败', lastError!);
    }
    notifyListeners();
  }

  /// 从 App Server 分页刷新当前工作区的活跃线程列表。
  /// Refreshes the current workspace's active thread list from App Server pages.
  Future<void> refreshThreads() async {
    final workspace = workspacePath;
    if (!_server.isRunning || workspace == null) return;
    final epoch = _threadRefreshEpoch;
    final request = ++_threadRefreshRequest;
    threadsLoading = true;
    threadsError = null;
    if (!_disposed) notifyListeners();
    try {
      final nextThreads = (await _server.listThreads(
        workingDirectory: workspace,
      )).map(CodexThread.fromJson).toList(growable: false);
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
      final nextThreads = (await _server.listThreads(
        workingDirectory: workspace,
        archived: true,
      )).map(CodexThread.fromJson).toList(growable: false);
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
    if (activeThreadId == thread.id) return;
    status = RuntimeStatus.starting;
    final previousThreadId = activeThreadId;
    lastError = null;
    _clearStreamingState();
    _add(TimelineKind.system, '正在恢复任务', thread.title);
    notifyListeners();
    try {
      final resumeResult = await _server.resumeThread(
        threadId: thread.id,
        modelProvider: thread.modelProvider,
        model: thread.model,
        config: _threadConfig(
          usesRelay:
              thread.modelProvider == RelayProviderConfiguration.providerId,
          model: thread.model,
          useDefaultModelWhenMissing: false,
        ),
      );
      activeThreadId = thread.id;
      status = RuntimeStatus.ready;
      final history = await _loadThreadHistory(
        threadId: thread.id,
        resumeResult: resumeResult,
      );
      _resetConversationTimeline();
      _appendThreadHistory(history);
      final incompleteItemTurnCount =
          history['incompleteItemTurnCount'] as int? ?? 0;
      final incompleteTurnHistory = history['incompleteTurnHistory'] == true;
      if (incompleteTurnHistory || incompleteItemTurnCount > 0) {
        final detail = [
          if (incompleteTurnHistory) '部分历史 turns',
          if (incompleteItemTurnCount > 0)
            '$incompleteItemTurnCount 个 turn 的 items',
        ].join('和');
        _add(TimelineKind.system, '历史内容未完全加载', '$detail 超出安全页数限制。');
      }
      _add(TimelineKind.system, '任务已恢复', '可以继续在此任务中追问。');
      await refreshThreads();
    } catch (error) {
      activeThreadId = previousThreadId;
      status = RuntimeStatus.ready;
      lastError = _messageOf(error);
      _add(TimelineKind.error, '无法恢复任务', lastError!);
    }
    notifyListeners();
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
    if (!_server.isRunning || status == RuntimeStatus.running) return;
    try {
      await _server.archiveThread(threadId: thread.id);
      if (activeThreadId == thread.id) {
        activeThreadId = null;
        _resetConversationTimeline();
        _clearStreamingState();
      }
      threads = threads
          .where((value) => value.id != thread.id)
          .toList(growable: false);
      _add(TimelineKind.system, '任务已归档', thread.title);
    } catch (error) {
      lastError = _messageOf(error);
      _add(TimelineKind.error, '归档失败', lastError!);
    }
    notifyListeners();
  }

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

  /// 验证并保存中转站设置，然后将其应用于后续新线程。
  /// Validates and saves relay settings, applying them to subsequent new threads.
  Future<void> saveRelayProvider({
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    if (canStopRuntime) {
      relayError = '请先停止运行时，再修改中转站配置。';
      notifyListeners();
      return;
    }
    final existingKey = relayProvider?.apiKey;
    final key = apiKey.trim().isEmpty ? existingKey : apiKey.trim();
    if (key == null || key.isEmpty) {
      relayError = '请输入中转站 API Key。';
      notifyListeners();
      return;
    }
    final modelName = model.trim();
    if (modelName.isEmpty) {
      relayError = '请输入中转站提供的模型名称。';
      notifyListeners();
      return;
    }

    relaySaving = true;
    relayError = null;
    notifyListeners();
    try {
      final configuration = RelayProviderConfiguration(
        baseUrl: RelayProviderConfiguration.normalizeBaseUrl(baseUrl),
        model: modelName,
        apiKey: key,
      );
      await _relayProviderStore.save(configuration);
      relayProvider = configuration;
      _add(TimelineKind.system, '中转站已配置', '将在下次启动运行时后生效。');
    } catch (error) {
      relayError = _messageOf(error);
    } finally {
      relaySaving = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 清除 Keychain 中的中转站设置，并恢复 OpenAI 默认 Provider。
  /// Clears relay settings from Keychain and restores the default OpenAI provider.
  Future<void> clearRelayProvider() async {
    if (canStopRuntime) {
      relayError = '请先停止运行时，再移除中转站配置。';
      notifyListeners();
      return;
    }
    relaySaving = true;
    relayError = null;
    notifyListeners();
    try {
      await _relayProviderStore.clear();
      relayProvider = null;
      _add(TimelineKind.system, '中转站已移除', '下次启动将使用默认 OpenAI Provider。');
    } catch (error) {
      relayError = _messageOf(error);
    } finally {
      relaySaving = false;
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
          : '将用于后续新建或恢复的任务：${value.label}。',
    );
    notifyListeners();
    try {
      await _saveReasoningEffort(value);
    } catch (error) {
      _add(TimelineKind.error, '无法保存推理强度', _messageOf(error));
      if (!_disposed) notifyListeners();
    }
  }

  /// 探测当前 Codex CLI 路径及其可用性。
  /// Probes the current Codex CLI path and availability.
  Future<void> inspectRuntime() async {
    await _runtimeLoad;
    await _inspectRuntime(notify: true);
  }

  /// 验证并保存用户指定的 Codex CLI 可执行文件路径。
  /// Validates and saves a user-specified Codex CLI executable path.
  Future<void> setRuntimeExecutable(String path) async {
    if (!canConfigureRuntime) {
      runtimeError = '请先停止运行时，再修改 Codex CLI 路径。';
      notifyListeners();
      return;
    }
    await _runtimeLoad;
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
    }
  }

  /// 清除自定义 CLI 路径，恢复自动发现。
  /// Clears the custom CLI path and restores automatic discovery.
  Future<void> resetRuntimeExecutable() async {
    if (!canConfigureRuntime) {
      runtimeError = '请先停止运行时，再修改 Codex CLI 路径。';
      notifyListeners();
      return;
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

  /// 更新审批策略；自动模式会立即处理之后收到的审批请求。
  /// Updates the approval policy; auto mode immediately handles later approval requests.
  void setApprovalMode(ApprovalMode mode) {
    if (approvalMode == mode) return;
    approvalMode = mode;
    _add(
      TimelineKind.system,
      '审批模式已更新',
      mode == ApprovalMode.autoApprove
          ? '后续命令、文件变更和额外权限请求将自动批准。'
          : '后续请求需要逐次确认。',
    );
    if (mode == ApprovalMode.autoApprove && pendingApproval != null) {
      unawaited(respondToApproval(accepted: true));
    }
    notifyListeners();
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
      case 'item/completed':
        _recordCompletedFileChange(event.params['item']);
      case 'turn/diff/updated':
        _updateTurnDiff(event.params['diff']);
      case 'turn/completed':
        _handleTurnCompleted(event.params);
        unawaited(refreshThreads());
      case 'thread/archived':
      case 'thread/unarchived':
      case 'thread/name/updated':
        unawaited(refreshThreads());
        unawaited(refreshArchivedThreads());
      case 'runtime/stderr':
        _add(
          TimelineKind.system,
          '运行时日志',
          event.params['message']?.toString() ?? '',
        );
      case 'runtime/exited':
        status = RuntimeStatus.failed;
        lastError = 'Codex runtime 已退出（code ${event.params['code']}）。';
        _add(TimelineKind.error, '运行时已断开', lastError!);
      case 'serverRequest/resolved':
        if (event.params['requestId'] == pendingApproval?.requestId) {
          pendingApproval = null;
          approvalResponding = false;
        }
      default:
        if (event.method.contains('command')) {
          _add(TimelineKind.command, '执行事件', event.method);
        }
    }
    notifyListeners();
  }

  @visibleForTesting
  /// 将服务器事件注入控制器，供测试验证事件处理。
  /// Injects a server event into the controller for event-handling tests.
  void handleServerEventForTesting(ServerEvent event) =>
      _handleServerEvent(event);

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
    pendingApproval = null;
    approvalResponding = false;
    switch (completionStatus) {
      case 'failed':
        status = RuntimeStatus.failed;
        lastError = _findText(turnMap['error']).isNotEmpty
            ? _findText(turnMap['error'])
            : 'Codex 未能完成当前任务。';
        _add(TimelineKind.error, '任务失败', lastError!);
      case 'interrupted':
        status = RuntimeStatus.ready;
        _add(TimelineKind.system, '任务已停止', '可以继续在同一线程追问。');
      default:
        status = RuntimeStatus.ready;
        _add(TimelineKind.system, '任务完成', '你可以继续在同一线程追问。');
    }
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
            final command = item['command']?.toString() ?? '';
            final output = item['aggregatedOutput']?.toString() ?? '';
            final detail = [
              command,
              output,
            ].where((value) => value.isNotEmpty).join('\n');
            if (detail.isNotEmpty) {
              _add(TimelineKind.command, '执行命令', detail);
            }
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
    }
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

  /// 从原始文件变更协议值生成简短的可读描述。
  /// Creates a short readable description from a raw file-change protocol value.
  String _describeFileChange(Object? value) {
    if (value is! Map) return '';
    final path =
        value['path']?.toString() ?? value['filePath']?.toString() ?? '';
    final kind =
        value['kind']?.toString() ?? value['type']?.toString() ?? 'changed';
    return path.isEmpty ? kind : '$kind $path';
  }

  /// 从任务完成项中提取并记录文件变更。
  /// Extracts and records file changes from a completed-turn item.
  void _recordCompletedFileChange(Object? rawItem) {
    if (rawItem is! Map || rawItem['type']?.toString() != 'fileChange') {
      return;
    }
    _recordFileChanges(rawItem['changes']);
  }

  /// 合并服务器文件变更，并向时间线写入变更摘要。
  /// Merges server file changes and writes a change summary to the timeline.
  void _recordFileChanges(Object? rawChanges) {
    if (rawChanges is! Iterable) return;
    final details = <String>[];
    for (final rawChange in rawChanges) {
      if (rawChange is! Map) continue;
      final change = CodexFileChange.fromJson(rawChange);
      if (change.path.isEmpty) continue;
      final previous = _fileChangesByPath[change.path];
      _fileChangesByPath[change.path] = change.diff.isEmpty && previous != null
          ? previous.copyWith(kind: change.kind)
          : change;
      final detail = _describeFileChange(rawChange);
      if (detail.isNotEmpty) details.add(detail);
    }
    if (details.isNotEmpty) {
      _add(TimelineKind.command, '文件变更', details.join('\n'));
    }
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

  /// 从 Keychain 加载中转站配置，并将读取失败显示给界面。
  /// Loads relay configuration from Keychain and surfaces read failures to the UI.
  Future<void> _loadRelayProvider() async {
    try {
      relayProvider = await _relayProviderStore.read();
    } catch (error) {
      relayError = '无法读取 Keychain 中的中转站配置：${_messageOf(error)}';
    } finally {
      relayLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 加载本地运行时路径和推理强度偏好。
  /// Loads local runtime-path and reasoning-effort preferences.
  Future<void> _loadRuntimeConfiguration() async {
    try {
      final values = await Future.wait([
        _runtimeConfigurationStore.readExecutable(),
        _runtimeConfigurationStore.readReasoningEffort(),
      ]);
      final executable = values[0];
      if (executable != null && executable.trim().isNotEmpty) {
        _server.setExecutable(executable);
      }
      reasoningEffort = ReasoningEffortLabel.fromConfigValue(values[1]);
      if (reasoningEffort != ReasoningEffort.defaultValue) {
        reasoningEffortOptions = [
          ReasoningEffort.defaultValue,
          reasoningEffort,
        ];
      }
    } catch (error) {
      runtimeError = '无法读取已保存的运行时配置：${_messageOf(error)}';
    }
  }

  /// 构建新建或恢复线程时可选的 Provider 与推理配置。
  /// Builds optional provider and reasoning configuration for a new or resumed thread.
  JsonMap? _threadConfig({
    required bool usesRelay,
    required bool useDefaultModelWhenMissing,
    String? model,
  }) {
    final effort = reasoningEffort.configValue;
    final config = <String, dynamic>{
      if (usesRelay && relayProvider != null) ...relayProvider!.threadConfig,
      if (effort != null &&
          _supportsReasoningEffort(
            model,
            reasoningEffort,
            useDefaultModelWhenMissing: useDefaultModelWhenMissing,
          ))
        'model_reasoning_effort': effort,
    };
    return config.isEmpty ? null : config;
  }

  /// 判断指定或默认模型是否支持给定的推理强度。
  /// Determines whether the specified or default model supports a reasoning effort.
  bool _supportsReasoningEffort(
    String? model,
    ReasoningEffort effort, {
    required bool useDefaultModelWhenMissing,
  }) {
    final modelId =
        model ?? (useDefaultModelWhenMissing ? _defaultModelId : null);
    return modelId != null &&
        (_reasoningEffortsByModel[modelId]?.contains(effort) ?? false);
  }

  /// 从模型列表刷新可用推理强度，并降级失效的已保存选择。
  /// Refreshes available reasoning efforts from models and downgrades an invalid saved choice.
  Future<void> _refreshReasoningEffortCapabilities() async {
    try {
      final models = await _server.listModels();
      final capabilities = <String, Set<ReasoningEffort>>{};
      String? defaultModelId;
      for (final model in models) {
        final id = model['id']?.toString() ?? model['model']?.toString();
        if (id == null || id.isEmpty) continue;
        final options = <ReasoningEffort>{};
        final supported = model['supportedReasoningEfforts'];
        if (supported is Iterable) {
          for (final rawOption in supported) {
            if (rawOption is! Map) continue;
            final effort = ReasoningEffortLabel.fromConfigValue(
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
        if (model['isDefault'] == true) defaultModelId ??= id;
      }
      _reasoningEffortsByModel = capabilities;
      _defaultModelId =
          defaultModelId ??
          (models.isEmpty
              ? null
              : (models.first['id'] ?? models.first['model'])?.toString());
      final activeModel = relayProvider?.model ?? _defaultModelId;
      final availableEfforts = [...?_reasoningEffortsByModel[activeModel]]
        ..sort((left, right) => left.index.compareTo(right.index));
      reasoningEffortOptions = [
        ReasoningEffort.defaultValue,
        ...availableEfforts,
      ];
      if (!reasoningEffortOptions.contains(reasoningEffort)) {
        reasoningEffort = ReasoningEffort.defaultValue;
        _add(TimelineKind.system, '推理强度已恢复为默认', '当前模型不支持已保存的推理强度。');
      }
    } catch (error) {
      _reasoningEffortsByModel = const {};
      _defaultModelId = null;
      reasoningEffortOptions = const [ReasoningEffort.defaultValue];
      if (reasoningEffort != ReasoningEffort.defaultValue) {
        reasoningEffort = ReasoningEffort.defaultValue;
      }
      _add(TimelineKind.system, '无法加载推理强度选项', '将使用模型默认值。');
    }
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

  @visibleForTesting
  /// 刷新模型能力，供测试验证推理强度选择。
  /// Refreshes model capabilities for reasoning-effort tests.
  Future<void> refreshReasoningEffortCapabilitiesForTesting() {
    return _refreshReasoningEffortCapabilities();
  }

  /// 恢复上次有效的本地项目路径，失效路径会被自动清除。
  /// Restores the last valid local workspace path and clears an invalid one.
  Future<void> _loadWorkspace() async {
    try {
      final storedPath = await _runtimeConfigurationStore.readWorkspace();
      if (storedPath == null || storedPath.trim().isEmpty) return;
      final directory = Directory(storedPath.trim());
      if (!await directory.exists()) {
        await _runtimeConfigurationStore.clearWorkspace();
        _add(TimelineKind.system, '已清除无效项目记录', storedPath.trim());
        return;
      }
      final canonicalPath = await directory.resolveSymbolicLinks();
      if (workspacePath != null) return;
      workspacePath = canonicalPath;
      _add(TimelineKind.system, '已恢复上次项目', canonicalPath);
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
      final snapshot = await _conversationHistoryStore.read(workspace);
      if (_disposed || workspacePath != workspace || snapshot == null) return;
      threads = snapshot.threads;
      archivedThreads = snapshot.archivedThreads;
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
    return Future.wait([
      _relayLoad,
      _runtimeLoad,
      _workspaceLoad,
      _historyLoad,
    ]);
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

  /// 取消流式更新计时器并清除 Agent 条目索引。
  /// Cancels streaming timers and clears the Agent-entry index.
  void _clearStreamingState() {
    _agentEntryIndexByItem.clear();
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
    final snapshot = ConversationHistorySnapshot(
      threads: List.of(threads),
      archivedThreads: List.of(archivedThreads),
      entries: List.of(entries),
      fileChanges: List.of(fileChanges),
      turnDiff: turnDiff,
    );
    final previousSave = _historySave;
    final nextSave = () async {
      try {
        await previousSave;
      } catch (_) {
        // A failed older save must not prevent a newer snapshot from writing.
      }
      await _conversationHistoryStore.save(
        workspace: workspace,
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

  /// 清空当前任务的文件变更集合和统一 Diff。
  /// Clears the current task's file-change collection and unified diff.
  void _clearFileChanges() {
    _fileChangesByPath.clear();
    turnDiff = null;
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

  /// 创建带有当前时间戳的时间线条目。
  /// Creates a timeline entry stamped with the current time.
  TimelineEntry _entry(TimelineKind kind, String title, String detail) {
    return TimelineEntry(
      kind: kind,
      title: title,
      detail: detail,
      createdAt: DateTime.now(),
    );
  }

  /// 追加时间线条目并安排本地历史保存。
  /// Appends a timeline entry and schedules local history persistence.
  void _add(TimelineKind kind, String title, String detail) {
    _entries.add(_entry(kind, title, detail));
    _scheduleConversationHistorySave();
  }

  /// 释放计时器、事件订阅和 App Server 资源，并尝试保存最后的历史快照。
  /// Releases timers, event subscriptions, and App Server resources, while attempting a final history save.
  @override
  void dispose() {
    _historySaveTimer?.cancel();
    unawaited(_saveConversationHistory());
    _disposed = true;
    _clearStreamingState();
    unawaited(_eventSubscription?.cancel());
    unawaited(_server.dispose());
    super.dispose();
  }
}
