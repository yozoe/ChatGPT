import 'dart:async';
import 'dart:collection';

import 'package:chatgpt/src/app_controller_live_turn_activity.dart';

/// Owns the lifecycle and live snapshot for the optional workspace bridge.
///
/// File decoding, parent-thread filtering, and durable timeline projection stay
/// in the controller. This state only prevents overlapping polls, cancels the
/// periodic timer, and exposes the current bridge activities.
class CodexCollaborationBridgeState {
  CodexCollaborationBridgeState({
    this.refreshInterval = const Duration(milliseconds: 500),
  });

  final Duration refreshInterval;
  final LinkedHashMap<String, LiveTurnActivity> activities =
      LinkedHashMap<String, LiveTurnActivity>();

  Timer? _timer;
  String? _workspace;
  int _requestSequence = 0;

  String? get workspace => _workspace;

  void start(String workspace, void Function() refresh) {
    _timer?.cancel();
    _workspace = workspace;
    activities.clear();
    _requestSequence++;
    refresh();
    _timer = Timer.periodic(refreshInterval, (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _workspace = null;
    activities.clear();
    _requestSequence++;
  }

  /// Stops periodic polling while keeping the current workspace and request
  /// epoch for a deterministic test refresh.
  void pausePolling() {
    _timer?.cancel();
    _timer = null;
  }

  int beginRequest() => ++_requestSequence;

  bool isCurrent({required int request, required String workspace}) =>
      request == _requestSequence && workspace == _workspace;

  bool replaceActivities(Map<String, LiveTurnActivity> next) {
    final changed =
        next.length != activities.length ||
        next.entries.any((entry) {
          final current = activities[entry.key];
          final value = entry.value;
          return current?.label != value.label ||
              current?.detail != value.detail ||
              current?.status != value.status ||
              current?.linkedThreadId != value.linkedThreadId ||
              current?.prompt != value.prompt;
        });
    if (!changed) return false;
    activities
      ..clear()
      ..addAll(next);
    return true;
  }

  void dispose() => stop();
}
