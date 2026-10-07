import 'dart:async';

/// 管理本地运行时的有限退避重连计时器，不拥有运行时或线程状态。
/// Manages bounded runtime reconnect timers without owning runtime or thread state.
class CodexRuntimeReconnectCoordinator {
  CodexRuntimeReconnectCoordinator({
    required this.isDisposed,
    required this.canSchedule,
    required this.reconnect,
    required this.onScheduled,
    this.delays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
    ],
  });

  final bool Function() isDisposed;
  final bool Function() canSchedule;
  final Future<void> Function() reconnect;
  final void Function(Duration delay) onScheduled;
  final List<Duration> delays;

  Timer? _timer;
  int _attempt = 0;

  /// 是否已有重连回调正在等待退避时间。
  /// Whether a reconnect callback is currently waiting for its delay.
  bool get isScheduled => _timer != null;

  /// 取消等待中的回调，但保留已消耗的尝试次数。
  /// Cancels a pending callback while retaining the attempt count.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// 在连接成功或手动检查后重置有限退避次数。
  /// Resets the bounded backoff after a successful connection or manual check.
  void resetAttempts() {
    _attempt = 0;
  }

  /// 在所有者仍允许时安排下一次有限退避重连。
  /// Schedules the next bounded reconnect attempt if the owner still permits it.
  void schedule() {
    if (isDisposed() || !canSchedule() || isScheduled) return;
    if (_attempt >= delays.length) return;
    final delay = delays[_attempt++];
    onScheduled(delay);
    _timer = Timer(delay, () {
      _timer = null;
      if (isDisposed() || !canSchedule()) return;
      unawaited(reconnect());
    });
  }

  /// 取消等待中的工作并释放计时器所有权。
  /// Cancels pending work and releases timer ownership.
  void dispose() {
    cancel();
  }
}
