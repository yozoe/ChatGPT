import 'package:chatgpt/src/app_controller_reasoning_summary_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps indexed fragments separate and appends deltas', () {
    final state = CodexReasoningSummaryState();

    state.ensurePart('reasoning-1', 1);
    expect(state.appendDelta('reasoning-1', 1, 'Plan'), 'Plan');
    expect(state.appendDelta('reasoning-1', 1, ' next'), 'Plan next');
    expect(state.partsByItem['reasoning-1'], {1: 'Plan next'});
  });

  test('clones nested fragments and clears the original independently', () {
    final state = CodexReasoningSummaryState()
      ..partsByItem['reasoning-1'] = {0: 'Planning'};

    final clone = state.clone();
    clone.partsByItem['reasoning-1']![0] = 'Changed';
    clone.clear();

    expect(state.partsByItem['reasoning-1']![0], 'Planning');
    expect(state.partsByItem, isNotEmpty);
  });

  test('removes one item without affecting other summaries', () {
    final state = CodexReasoningSummaryState()
      ..partsByItem['reasoning-1'] = {0: 'One'}
      ..partsByItem['reasoning-2'] = {0: 'Two'};

    state.removeItem('reasoning-1');

    expect(state.partsByItem, {
      'reasoning-2': {0: 'Two'},
    });
  });
}
