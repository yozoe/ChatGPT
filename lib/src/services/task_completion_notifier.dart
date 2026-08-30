import 'package:flutter/services.dart';

/// Bridges task-completion feedback to the desktop host.
///
/// Unsupported hosts deliberately ignore the calls so the shared controller
/// remains usable in widget tests and on platforms without a desktop bridge.
class TaskCompletionNotifier {
  TaskCompletionNotifier({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'codex_desk/task_completion';
  final MethodChannel _channel;

  /// Shows the system notification emitted for a successfully completed task.
  Future<void> notifyTaskCompleted() => _invoke('notifyTaskCompleted');

  /// Shows or hides the macOS Dock completion badge.
  Future<void> setDockBadge({required bool visible}) =>
      _invoke('setDockBadge', <String, bool>{'visible': visible});

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
