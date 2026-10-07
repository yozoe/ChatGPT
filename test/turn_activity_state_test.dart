import 'package:chatgpt/src/app_controller_live_turn_activity.dart';
import 'package:chatgpt/src/app_controller_turn_activity_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clones nested activity state without sharing collections', () {
    const activity = LiveTurnActivity(
      itemId: 'command-1',
      kind: 'commandExecution',
      label: '正在运行命令',
      detail: 'flutter test',
    );
    final state = CodexTurnActivityState()
      ..activeCommand = 'flutter test'
      ..activeCommandItemId = activity.itemId
      ..activeActivity = activity
      ..collaborationActivities['agent-1'] = const LiveTurnActivity(
        itemId: 'agent-1',
        kind: 'subAgentActivity',
        label: 'Reviewer',
      )
      ..reasoningSummaryParts['reasoning-1'] = {0: 'Planning'}
      ..completedCommandItemIds.add('command-0')
      ..completedPlanItemIds.add('plan-0');

    final clone = state.clone();
    clone.collaborationActivities.clear();
    clone.reasoningSummaryParts['reasoning-1']![0] = 'Changed';
    clone.completedCommandItemIds.add('command-1');

    expect(state.collaborationActivities, hasLength(1));
    expect(state.reasoningSummaryParts['reasoning-1']![0], 'Planning');
    expect(state.completedCommandItemIds, {'command-0'});
    expect(clone.activeActivity, same(activity));
  });

  test('clear resets every per-turn activity field', () {
    final state = CodexTurnActivityState()
      ..activeCommand = 'dart test'
      ..activeCommandItemId = 'command-1'
      ..activeActivity = const LiveTurnActivity(
        itemId: 'command-1',
        kind: 'commandExecution',
        label: '正在运行命令',
      )
      ..collaborationActivities['agent-1'] = const LiveTurnActivity(
        itemId: 'agent-1',
        kind: 'subAgentActivity',
        label: 'Reviewer',
      )
      ..reasoningSummaryParts['reasoning-1'] = {0: 'Planning'}
      ..completedCommandItemIds.add('command-1')
      ..completedPlanItemIds.add('plan-1');

    state.clear();

    expect(state.activeCommand, isNull);
    expect(state.activeCommandItemId, isNull);
    expect(state.activeActivity, isNull);
    expect(state.collaborationActivities, isEmpty);
    expect(state.reasoningSummaryParts, isEmpty);
    expect(state.completedCommandItemIds, isEmpty);
    expect(state.completedPlanItemIds, isEmpty);
  });
}
