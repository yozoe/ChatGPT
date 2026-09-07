import 'dart:async';
import 'dart:math' as math;

import 'package:chatgpt/src/domain/scheduled_task.dart';
import 'package:chatgpt/src/services/codex_clock.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';

/// Owns local scheduled-task timing, persistence, retry, and cancellation.
class ScheduledTaskCoordinator {
  ScheduledTaskCoordinator({
    required RuntimeConfigurationStore store,
    required CodexClock clock,
    required bool Function() isDisposed,
    required bool Function() hasRunningTasks,
    required String? Function() currentWorkspace,
    required Future<bool> Function(String workspace) selectWorkspace,
    required bool Function() canSend,
    required Future<bool> Function(String prompt) send,
    required void Function(String title, String detail) reportError,
    required void Function(String title, String detail) reportSystem,
    required void Function() notifyChanged,
    required String Function(Object error) describeError,
  }) : _store = store,
       _clock = clock,
       _isDisposed = isDisposed,
       _hasRunningTasks = hasRunningTasks,
       _currentWorkspace = currentWorkspace,
       _selectWorkspace = selectWorkspace,
       _canSend = canSend,
       _send = send,
       _reportError = reportError,
       _reportSystem = reportSystem,
       _notifyChanged = notifyChanged,
       _describeError = describeError;

  final RuntimeConfigurationStore _store;
  final CodexClock _clock;
  final bool Function() _isDisposed;
  final bool Function() _hasRunningTasks;
  final String? Function() _currentWorkspace;
  final Future<bool> Function(String workspace) _selectWorkspace;
  final bool Function() _canSend;
  final Future<bool> Function(String prompt) _send;
  final void Function(String title, String detail) _reportError;
  final void Function(String title, String detail) _reportSystem;
  final void Function() _notifyChanged;
  final String Function(Object error) _describeError;
  final List<ScheduledTask> _tasks = [];
  final Map<String, Timer> _timers = {};
  final Set<String> _dispatchingIds = {};

  /// Returns an immutable, time-ordered scheduled-task snapshot.
  List<ScheduledTask> get tasks => List.unmodifiable(_tasks);

  /// Whether a task has crossed the point where cancellation is unsafe.
  bool isDispatching(String id) => _dispatchingIds.contains(id);

  /// Replaces the persisted task snapshot and arms every pending task.
  void load(Iterable<ScheduledTask> tasks) {
    _cancelTimers();
    _tasks
      ..clear()
      ..addAll(tasks);
    _sort();
    for (final task in _tasks) {
      _arm(task);
    }
  }

  /// Validates, persists, and arms a task for the active workspace.
  Future<bool> schedule({
    required String prompt,
    required DateTime runAt,
  }) async {
    final text = prompt.trim();
    final workspace = _currentWorkspace();
    if (text.isEmpty || workspace == null || !runAt.isAfter(_clock.now())) {
      return false;
    }
    final task = ScheduledTask(
      id: '${_clock.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}',
      workspacePath: workspace,
      prompt: text,
      runAt: runAt,
    );
    _tasks.add(task);
    _sort();
    _arm(task);
    try {
      await _save();
    } catch (error) {
      _tasks.removeWhere((value) => value.id == task.id);
      _timers.remove(task.id)?.cancel();
      _reportError('已安排任务保存失败', '无法保存已安排任务：${_describeError(error)}');
      _notifyChanged();
      return false;
    }
    _reportSystem('已安排任务', '将在 ${task.runAt} 发送到项目 $workspace。');
    _notifyChanged();
    return true;
  }

  /// Cancels an unsent task and restores it if persistence fails.
  Future<void> cancel(String id) async {
    if (_dispatchingIds.contains(id)) {
      _reportError('无法取消已安排任务', '该已安排任务正在发送，无法再取消。');
      if (!_isDisposed()) _notifyChanged();
      return;
    }
    final removed = _taskById(id);
    if (removed == null) return;
    _tasks.remove(removed);
    _timers.remove(id)?.cancel();
    try {
      await _save();
    } catch (error) {
      _tasks.add(removed);
      _sort();
      _arm(removed);
      _reportError('取消已安排任务失败', '无法取消已安排任务：${_describeError(error)}');
    }
    if (!_isDisposed()) _notifyChanged();
  }

  /// Drives one task immediately for deterministic tests.
  Future<void> dispatchForTesting(String id) => _dispatch(id);

  /// Cancels all owned timers before the containing controller is disposed.
  void dispose() => _cancelTimers();

  void _sort() =>
      _tasks.sort((left, right) => left.runAt.compareTo(right.runAt));

  ScheduledTask? _taskById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Future<void> _save() => _store.saveScheduledTasks(_tasks);

  void _arm(ScheduledTask task) {
    _timers.remove(task.id)?.cancel();
    final delay = task.runAt.difference(_clock.now());
    _timers[task.id] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_dispatch(task.id)),
    );
  }

  void _retry(String id) {
    _timers[id]?.cancel();
    _timers[id] = Timer(
      const Duration(minutes: 1),
      () => unawaited(_dispatch(id)),
    );
  }

  Future<void> _dispatch(String id) async {
    _timers.remove(id)?.cancel();
    final task = _taskById(id);
    if (task == null || _isDisposed()) return;
    if (_hasRunningTasks()) {
      _retry(id);
      return;
    }
    if (task.workspacePath != _currentWorkspace()) {
      final switched = await _selectWorkspace(task.workspacePath);
      if (_isDisposed() || _taskById(id) == null) return;
      if (!switched || _currentWorkspace() != task.workspacePath) {
        _retry(id);
        return;
      }
    }
    if (!_canSend()) {
      _retry(id);
      return;
    }
    _dispatchingIds.add(id);
    late final bool sent;
    try {
      sent = await _send(task.prompt);
    } finally {
      _dispatchingIds.remove(id);
    }
    if (!sent) {
      _retry(id);
      return;
    }
    _tasks.removeWhere((value) => value.id == id);
    try {
      await _save();
    } catch (error) {
      _reportError('已安排任务清理失败', '已安排任务已发送，但清理记录失败：${_describeError(error)}');
    }
    if (!_isDisposed()) _notifyChanged();
  }

  void _cancelTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
