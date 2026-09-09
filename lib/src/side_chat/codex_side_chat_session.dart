import 'dart:async';

import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/foundation.dart';

/// Owns one ephemeral App Server fork without replacing the main conversation.
class CodexSideChatSession extends ChangeNotifier {
  CodexSideChatSession({
    required CodexAppServer server,
    required this.parentThreadId,
    required this.threadId,
    required this.workingDirectory,
  }) : _server = server {
    _eventSubscription = _server.events.listen(handleServerEvent);
  }

  final CodexAppServer _server;
  final String parentThreadId;
  final String threadId;
  final String workingDirectory;
  final List<TimelineEntry> _entries = [];
  final Map<String, int> _agentEntryIndexByItem = {};
  late final StreamSubscription<ServerEvent> _eventSubscription;

  bool _disposed = false;
  bool _startingTurn = false;
  bool _running = false;
  bool _stopping = false;
  String? _activeTurnId;
  String? _lastError;

  List<TimelineEntry> get entries => List.unmodifiable(_entries);
  bool get isRunning => _running || _startingTurn;
  bool get isStopping => _stopping;
  bool get canSend => !_disposed && !_running && !_startingTurn;
  bool get canStop =>
      !_disposed && _running && !_stopping && _activeTurnId != null;
  String? get lastError => _lastError;

  /// Sends a real turn to the ephemeral fork while the parent chat stays active.
  Future<bool> send(String prompt) async {
    final text = prompt.trim();
    if (!canSend || text.isEmpty) return false;
    _startingTurn = true;
    _lastError = null;
    _entries.add(
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: text,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    try {
      await _server.startTurn(
        threadId: threadId,
        prompt: text,
        workingDirectory: workingDirectory,
      );
      if (_disposed) return false;
      _startingTurn = false;
      _running = true;
      notifyListeners();
      return true;
    } catch (error) {
      if (_disposed) return false;
      _startingTurn = false;
      _running = false;
      _lastError = error.toString();
      _entries.add(
        TimelineEntry(
          kind: TimelineKind.error,
          title: '无法发送侧边消息',
          detail: _lastError!,
          createdAt: DateTime.now(),
        ),
      );
      notifyListeners();
      return false;
    }
  }

  /// Interrupts the current side-chat turn when its server turn ID is known.
  Future<bool> stop() async {
    final turnId = _activeTurnId;
    if (!canStop || turnId == null) return false;
    _stopping = true;
    notifyListeners();
    try {
      await _server.interruptTurn(threadId: threadId, turnId: turnId);
      return true;
    } catch (error) {
      if (_disposed) return false;
      _lastError = error.toString();
      notifyListeners();
      return false;
    } finally {
      if (!_disposed) {
        _stopping = false;
        notifyListeners();
      }
    }
  }

  /// Applies only notifications explicitly attributed to this ephemeral fork.
  @visibleForTesting
  void handleServerEvent(ServerEvent event) {
    if (_disposed || _threadIdFrom(event.params) != threadId) return;
    switch (event.method) {
      case 'turn/started':
        final turn = event.params['turn'];
        final turnId = turn is Map ? turn['id']?.toString().trim() : null;
        _activeTurnId = turnId?.isEmpty == true ? null : turnId;
        _startingTurn = false;
        _running = true;
        _lastError = null;
      case 'item/agentMessage/delta':
        _appendAgentDelta(event.params);
      case 'item/completed':
        _recordCompletedAgentMessage(event.params['item']);
      case 'turn/completed':
        _startingTurn = false;
        _running = false;
        _stopping = false;
        _activeTurnId = null;
        final turn = event.params['turn'];
        final status = turn is Map ? turn['status']?.toString() : null;
        if (status == 'failed') {
          final error = turn is Map ? turn['error']?.toString() : null;
          _lastError = error?.trim().isNotEmpty == true ? error : '侧边聊天未能完成。';
        }
      case 'runtime/exited':
        _startingTurn = false;
        _running = false;
        _stopping = false;
        _activeTurnId = null;
        _lastError = 'Codex runtime 已断开。';
      default:
        return;
    }
    notifyListeners();
  }

  String? _threadIdFrom(Map<String, dynamic> params) {
    final direct = params['threadId']?.toString().trim();
    if (direct?.isNotEmpty == true) return direct;
    final thread = params['thread'];
    final nested = thread is Map ? thread['id']?.toString().trim() : null;
    return nested?.isNotEmpty == true ? nested : null;
  }

  void _appendAgentDelta(Map<String, dynamic> params) {
    final delta = params['delta']?.toString() ?? '';
    if (delta.isEmpty) return;
    final itemId = params['itemId']?.toString() ?? 'side-agent-message';
    final index = _agentEntryIndexByItem[itemId];
    if (index == null) {
      _agentEntryIndexByItem[itemId] = _entries.length;
      _entries.add(
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: delta,
          createdAt: DateTime.now(),
          sourceItemId: itemId,
        ),
      );
      return;
    }
    final previous = _entries[index];
    _entries[index] = previous.copyWith(detail: '${previous.detail}$delta');
  }

  void _recordCompletedAgentMessage(Object? rawItem) {
    if (rawItem is! Map || rawItem['type'] != 'agentMessage') return;
    final itemId = rawItem['id']?.toString() ?? '';
    final text = rawItem['text']?.toString() ?? '';
    if (text.isEmpty) return;
    final index = _agentEntryIndexByItem[itemId];
    if (index == null) {
      if (itemId.isNotEmpty) _agentEntryIndexByItem[itemId] = _entries.length;
      _entries.add(
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: text,
          createdAt: DateTime.now(),
          sourceItemId: itemId.isEmpty ? null : itemId,
        ),
      );
      return;
    }
    _entries[index] = _entries[index].copyWith(detail: text);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_eventSubscription.cancel());
    super.dispose();
  }
}
