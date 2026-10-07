import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_thread_operation_state.dart';

void main() {
  test('keeps thread operation guards independent', () {
    final state = CodexThreadOperationState();

    state.unarchivingThreadIds.add('restore');
    state.archivingThreadIds.add('archive');
    state.deletingThreadIds.add('delete');
    state.forkingThreadIds.add('fork');

    expect(state.unarchivingThreadIds, {'restore'});
    expect(state.archivingThreadIds, {'archive'});
    expect(state.deletingThreadIds, {'delete'});
    expect(state.forkingThreadIds, {'fork'});
  });
}
