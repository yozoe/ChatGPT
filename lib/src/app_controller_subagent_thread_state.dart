import 'dart:async';
import 'dart:collection';

import 'package:chatgpt/src/domain/subagent_thread_view.dart';

/// Owns the bounded cache and request lifecycle for read-only subagent views.
///
/// The controller still owns App Server I/O and history projection. This
/// container only tracks which child views are retained, which reads are
/// current, and which refresh timers are pending.
class CodexSubagentThreadState {
  CodexSubagentThreadState({this.maximumCacheEntries = 8});

  final int maximumCacheEntries;
  final LinkedHashMap<String, SubagentThreadView> _views =
      LinkedHashMap<String, SubagentThreadView>();
  final Map<String, int> _requests = <String, int>{};
  final Map<String, Timer> _refreshTimers = <String, Timer>{};
  int _requestSequence = 0;

  SubagentThreadView? view(String threadId) {
    final current = _views.remove(threadId);
    if (current != null) _views[threadId] = current;
    return current;
  }

  SubagentThreadView? peek(String threadId) => _views[threadId];

  Iterable<SubagentThreadView> get views => _views.values;

  void store(SubagentThreadView view) {
    _views
      ..remove(view.threadId)
      ..[view.threadId] = view;
    while (_views.length > maximumCacheEntries) {
      final evictedThreadId = _views.keys.first;
      _views.remove(evictedThreadId);
      _requests.remove(evictedThreadId);
      _refreshTimers.remove(evictedThreadId)?.cancel();
    }
  }

  int beginRequest(String threadId) {
    final request = ++_requestSequence;
    _requests[threadId] = request;
    return request;
  }

  bool isCurrentRequest(String threadId, int request) =>
      _requests[threadId] == request;

  void clear() {
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _refreshTimers.clear();
    _requests.clear();
    _views.clear();
  }

  void invalidateForRuntimeChange({
    required String error,
    required String workingStatus,
  }) {
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _refreshTimers.clear();
    _requests.clear();
    final retained = _views.values.toList(growable: false);
    for (final view in retained) {
      _views[view.threadId] = view.copyWith(
        status: view.status == workingStatus ? 'stopped' : view.status,
        loading: false,
        error: error,
      );
    }
  }

  void scheduleRefresh(String threadId, void Function() callback) {
    final view = _views[threadId];
    if (view == null) return;
    _refreshTimers.remove(threadId)?.cancel();
    _refreshTimers[threadId] = Timer(const Duration(milliseconds: 160), () {
      _refreshTimers.remove(threadId);
      callback();
    });
  }

  void dispose() => clear();
}
