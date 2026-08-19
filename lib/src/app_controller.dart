import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'domain/pending_approval.dart';
import 'domain/timeline_entry.dart';
import 'services/codex_app_server.dart';

enum RuntimeStatus { stopped, starting, ready, running, failed }

class CodexController extends ChangeNotifier {
  CodexController({CodexAppServer? server})
    : _server = server ?? CodexAppServer() {
    _entries.add(
      _entry(
        TimelineKind.system,
        '欢迎使用 Codex Desk',
        '选择本地项目后启动 Codex App Server。应用不会保存你的 API Key。',
      ),
    );
  }

  final CodexAppServer _server;
  StreamSubscription<ServerEvent>? _eventSubscription;
  final List<TimelineEntry> _entries = [];
  final Map<String, int> _agentEntryIndexByItem = {};
  Timer? _deltaNotificationTimer;
  bool _disposed = false;

  RuntimeStatus status = RuntimeStatus.stopped;
  String? workspacePath;
  String? activeThreadId;
  String? lastError;
  PendingApproval? pendingApproval;
  bool approvalResponding = false;

  List<TimelineEntry> get entries => List.unmodifiable(_entries);
  bool get canSend => status == RuntimeStatus.ready && workspacePath != null;
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
    workspacePath = canonicalPath;
    activeThreadId = null;
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
    if (status == RuntimeStatus.ready || status == RuntimeStatus.running) {
      return;
    }

    status = RuntimeStatus.starting;
    lastError = null;
    _add(TimelineKind.system, '正在启动本地运行时', 'codex app-server · $workspace');
    notifyListeners();

    try {
      _eventSubscription ??= _server.events.listen(_handleServerEvent);
      if (_server.isRunning) await _server.stop();
      await _server.start(workingDirectory: workspace);
      await _server.initialize();
      status = RuntimeStatus.ready;
      _add(TimelineKind.system, '运行时已连接', 'App Server 已通过本地 stdio 通道就绪。');
    } catch (error) {
      status = RuntimeStatus.failed;
      lastError = _messageOf(error);
      _add(TimelineKind.error, '无法启动运行时', lastError!);
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
      activeThreadId ??= await _server.startThread(workingDirectory: workspace);
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
      case 'item/agentMessage/delta':
        _appendAgentDelta(event.params);
        _scheduleDeltaNotification();
        return;
      case 'turn/completed':
        _handleTurnCompleted(event.params);
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

  void _clearStreamingState() {
    _agentEntryIndexByItem.clear();
    _deltaNotificationTimer?.cancel();
    _deltaNotificationTimer = null;
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
