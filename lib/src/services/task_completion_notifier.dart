import 'package:flutter/services.dart';

/// Bridges task-completion feedback to the desktop host.
///
/// Unsupported hosts deliberately ignore the calls so the shared controller
/// remains usable in widget tests and on platforms without a desktop bridge.
class TaskCompletionNotifier {
  TaskCompletionNotifier({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'dockActivated':
          _dockActivationHandler?.call();
        case 'openSettings':
          _openSettingsHandler?.call();
      }
    });
  }

  static const _channelName = 'codex_desk/task_completion';
  final MethodChannel _channel;
  void Function()? _dockActivationHandler;
  void Function()? _openSettingsHandler;

  /// Receives a host activation event, including a click on the running app's
  /// Dock icon. Only one workspace is expected to own this channel at a time.
  void setDockActivationHandler(void Function()? handler) {
    _dockActivationHandler = handler;
  }

  void setOpenSettingsHandler(void Function()? handler) {
    _openSettingsHandler = handler;
  }

  /// Shows the system notification emitted for a successfully completed task.
  Future<void> notifyTaskCompleted() => _invoke('notifyTaskCompleted');

  /// Shows or hides the macOS Dock completion badge.
  Future<void> setDockBadge({required bool visible, int? count}) => _invoke(
    'setDockBadge',
    <String, Object>{'visible': visible, 'count': ?count},
  );

  /// 设置 macOS Dock 完成徽标中显示的数字。
  /// Sets the numeric count shown in the macOS Dock completion badge.
  Future<void> setDockBadgeCount(int count) =>
      setDockBadge(visible: count > 0, count: count);

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // The platform does not provide desktop completion feedback.
    } on PlatformException {
      // Notification permission and host failures must not affect a turn.
    }
  }
}
