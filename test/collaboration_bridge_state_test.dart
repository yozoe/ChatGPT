import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_collaboration_bridge_state.dart';
import 'package:chatgpt/src/app_controller_live_turn_activity.dart';

void main() {
  const activity = LiveTurnActivity(
    itemId: 'bridge-1',
    kind: 'collabToolCall',
    label: 'review',
    status: 'working',
  );

  test('starts and stops a bridge polling epoch', () {
    final state = CodexCollaborationBridgeState(
      refreshInterval: const Duration(hours: 1),
    );
    var refreshCount = 0;

    state.start('/workspace', () => refreshCount++);
    final request = state.beginRequest();
    expect(refreshCount, 1);
    expect(state.workspace, '/workspace');
    expect(state.isCurrent(request: request, workspace: '/workspace'), isTrue);

    state.stop();

    expect(state.workspace, isNull);
    expect(state.activities, isEmpty);
    expect(state.isCurrent(request: request, workspace: '/workspace'), isFalse);
  });

  test('replaces only when bridge activities change', () {
    final state = CodexCollaborationBridgeState();

    expect(state.replaceActivities({'bridge-1': activity}), isTrue);
    expect(state.replaceActivities({'bridge-1': activity}), isFalse);
    expect(state.replaceActivities(const {}), isTrue);
  });

  test('pausing polling preserves the active bridge epoch', () {
    final state = CodexCollaborationBridgeState(
      refreshInterval: const Duration(milliseconds: 1),
    );
    var refreshCount = 0;
    state.start('/workspace', () => refreshCount++);
    final request = state.beginRequest();
    state.pausePolling();

    expect(state.workspace, '/workspace');
    expect(state.isCurrent(request: request, workspace: '/workspace'), isTrue);
    expect(refreshCount, 1);
  });
}
