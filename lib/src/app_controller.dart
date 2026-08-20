import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'domain/codex_thread.dart';
import 'domain/pending_approval.dart';
import 'domain/relay_provider_configuration.dart';
import 'domain/timeline_entry.dart';
import 'services/codex_app_server.dart';
import 'services/relay_provider_store.dart';
import 'services/runtime_configuration_store.dart';

enum RuntimeStatus { stopped, starting, ready, running, failed }

enum AuthStatus { checking, signedOut, chatgpt, apiKey, external }

class CodexController extends ChangeNotifier {
  CodexController({
    CodexAppServer? server,
    RelayProviderStore? relayProviderStore,
    RuntimeConfigurationStore? runtimeConfigurationStore,
  }) : _server = server ?? CodexAppServer(),
       _relayProviderStore = relayProviderStore ?? RelayProviderStore(),
       _runtimeConfigurationStore =
           runtimeConfigurationStore ?? RuntimeConfigurationStore() {
    _entries.add(
      _entry(
        TimelineKind.system,
        '欢迎使用 Codex Desk',
        '选择本地项目后启动 Codex App Server。密钥不会写入项目或日志。',
      ),
    );
    _relayLoad = _loadRelayProvider();
    _runtimeLoad = _loadRuntimeConfiguration();
  }

  final CodexAppServer _server;
  final RelayProviderStore _relayProviderStore;
  final RuntimeConfigurationStore _runtimeConfigurationStore;
  StreamSubscription<ServerEvent>? _eventSubscription;
  final List<TimelineEntry> _entries = [];
  final Map<String, int> _agentEntryIndexByItem = {};
  Timer? _deltaNotificationTimer;
  bool _disposed = false;
  bool _startingRuntime = false;
  int _threadRefreshEpoch = 0;
  int _threadRefreshRequest = 0;
  late final Future<void> _relayLoad;
  late final Future<void> _runtimeLoad;

  RuntimeStatus status = RuntimeStatus.stopped;
  String? workspacePath;
  String? activeThreadId;
  String? lastError;
  PendingApproval? pendingApproval;
  bool approvalResponding = false;
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

  List<TimelineEntry> get entries => List.unmodifiable(_entries);
  bool get canSend =>
      status == RuntimeStatus.ready &&
      workspacePath != null &&
      (!requiresOpenaiAuth || authStatus != AuthStatus.signedOut);
  bool get canStop => status == RuntimeStatus.running && activeThreadId != null;
  bool get canChooseWorkspace =>
      status == RuntimeStatus.stopped ||
      (status == RuntimeStatus.failed && !_server.isRunning);
  bool get canStopRuntime =>
      _server.isRunning ||
      status == RuntimeStatus.ready ||
      status == RuntimeStatus.running;
  bool get canRespondToApproval =>
      pendingApproval != null && !approvalResponding;
  String get authLabel => switch (authStatus) {
    AuthStatus.checking => '检查账户',
    AuthStatus.signedOut => '未登录',
    AuthStatus.chatgpt =>
      accountPlan == null ? 'ChatGPT' : 'ChatGPT $accountPlan',
    AuthStatus.apiKey => 'API Key',
    AuthStatus.external => '外部 Provider',
  };
  String get providerLabel => relayProvider == null ? 'OpenAI' : '中转站';
  bool get canConfigureRuntime =>
      !_startingRuntime &&
      status != RuntimeStatus.starting &&
      !_server.isRunning;

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
    _invalidateThreadRefreshes();
    workspacePath = canonicalPath;
    activeThreadId = null;
    threads = const [];
    _clearStreamingState();
    _add(TimelineKind.system, '项目已选择', canonicalPath);
    notifyListeners();
  }

  void createThread() {
    if (status != RuntimeStatus.ready || workspacePath == null) {
      lastError = '运行时就绪后才能新建任务。';
      notifyListeners();
      return;
    }
    activeThreadId = null;
    _clearStreamingState();
    _add(TimelineKind.system, '已新建任务', '发送第一条消息后会创建新的 Thread。');
    notifyListeners();
  }

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
      await Future.wait([_relayLoad, _runtimeLoad]);
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

  Future<void> sendPrompt(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || !canSend) return;
    final workspace = workspacePath!;
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
        config: relayProvider?.threadConfig,
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

  Future<void> stopRuntime() async {
    if (status == RuntimeStatus.stopped && !_server.isRunning) return;
    try {
      await _server.stop();
      _invalidateThreadRefreshes();
      status = RuntimeStatus.stopped;
      activeThreadId = null;
      threads = const [];
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
        config: thread.modelProvider == RelayProviderConfiguration.providerId
            ? relayProvider?.threadConfig
            : null,
      );
      activeThreadId = thread.id;
      status = RuntimeStatus.ready;
      _resetConversationTimeline();
      final history = await _loadThreadHistory(
        threadId: thread.id,
        resumeResult: resumeResult,
      );
      _appendThreadHistory(history);
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

  Future<void> inspectRuntime() async {
    await _runtimeLoad;
    await _inspectRuntime(notify: true);
  }

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

  Future<void> respondToApproval({required bool accepted}) async {
    final approval = pendingApproval;
    if (approval == null || approvalResponding) return;

    approvalResponding = true;
    notifyListeners();
    try {
      final result = switch (approval.kind) {
        ApprovalKind.command || ApprovalKind.fileChange => {
          'decision': accepted ? 'accept' : 'decline',
        },
        ApprovalKind.permissions => {
          'permissions': accepted && approval.params['permissions'] is Map
              ? JsonMap.from(approval.params['permissions'] as Map)
              : <String, dynamic>{},
          if (accepted) 'scope': 'turn',
        },
      };
      _server.respond(approval.requestId, result);
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

  void _handleServerEvent(ServerEvent event) {
    if (_disposed) return;
    if (event.isServerRequest) {
      final approval = PendingApproval.fromEvent(event);
      if (approval == null) {
        _server.respondError(event.requestId!, '此客户端暂不支持 ${event.method}。');
        _add(TimelineKind.error, '未支持的运行时请求', event.method);
      } else {
        pendingApproval = approval;
        approvalResponding = false;
        _add(TimelineKind.approval, approval.title, approval.detail);
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
      case 'turn/completed':
        _handleTurnCompleted(event.params);
        unawaited(refreshThreads());
      case 'thread/archived':
      case 'thread/unarchived':
      case 'thread/name/updated':
        unawaited(refreshThreads());
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
  void handleServerEventForTesting(ServerEvent event) =>
      _handleServerEvent(event);

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
            final changes = item['changes'];
            final detail = changes is Iterable
                ? changes
                      .map(_describeFileChange)
                      .where((v) => v.isNotEmpty)
                      .join('\n')
                : '';
            if (detail.isNotEmpty) {
              _add(TimelineKind.command, '文件变更', detail);
            }
          case 'mcpToolCall' ||
              'dynamicToolCall' ||
              'webSearch' ||
              'imageView' ||
              'imageGeneration' ||
              'sleep' ||
              'enteredReviewMode' ||
              'exitedReviewMode':
            final detail = _findText(item);
            if (detail.isNotEmpty) {
              _add(TimelineKind.command, item['type']!.toString(), detail);
            }
        }
      }
    }
  }

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
    return {'turns': turns};
  }

  int _turnTimestamp(JsonMap turn) =>
      (turn['startedAt'] as num?)?.toInt() ??
      (turn['completedAt'] as num?)?.toInt() ??
      0;

  String _describeFileChange(Object? value) {
    if (value is! Map) return '';
    final path =
        value['path']?.toString() ?? value['filePath']?.toString() ?? '';
    final kind =
        value['kind']?.toString() ?? value['type']?.toString() ?? 'changed';
    return path.isEmpty ? kind : '$kind $path';
  }

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

  Future<void> _loadRuntimeConfiguration() async {
    try {
      final executable = await _runtimeConfigurationStore.readExecutable();
      if (executable != null && executable.trim().isNotEmpty) {
        _server.setExecutable(executable);
      }
    } catch (error) {
      runtimeError = '无法读取已保存的 Codex CLI 路径：${_messageOf(error)}';
    }
  }

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

  void _clearStreamingState() {
    _agentEntryIndexByItem.clear();
    _deltaNotificationTimer?.cancel();
    _deltaNotificationTimer = null;
  }

  void _resetConversationTimeline() {
    if (_entries.isEmpty) return;
    final welcome = _entries.first;
    _entries
      ..clear()
      ..add(welcome);
  }

  void _invalidateThreadRefreshes() {
    _threadRefreshEpoch++;
    _threadRefreshRequest++;
    threadsLoading = false;
    threadsError = null;
  }

  bool _isCurrentThreadRefresh(int request, int epoch, String workspace) {
    return !_disposed &&
        request == _threadRefreshRequest &&
        epoch == _threadRefreshEpoch &&
        workspacePath == workspace &&
        _server.isRunning;
  }

  void _scheduleDeltaNotification() {
    if (_deltaNotificationTimer != null || _disposed) return;
    _deltaNotificationTimer = Timer(const Duration(milliseconds: 50), () {
      _deltaNotificationTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  String _messageOf(Object error) =>
      error.toString().replaceFirst('Bad state: ', '');

  TimelineEntry _entry(TimelineKind kind, String title, String detail) {
    return TimelineEntry(
      kind: kind,
      title: title,
      detail: detail,
      createdAt: DateTime.now(),
    );
  }

  void _add(TimelineKind kind, String title, String detail) {
    _entries.add(_entry(kind, title, detail));
  }

  @override
  void dispose() {
    _disposed = true;
    _clearStreamingState();
    unawaited(_eventSubscription?.cancel());
    unawaited(_server.dispose());
    super.dispose();
  }
}
