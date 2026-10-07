import 'package:chatgpt/src/app_controller_thread_refresh_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps active and archived request markers independent', () {
    final state = CodexThreadRefreshState();

    expect(state.nextActiveRequest(), 1);
    expect(state.nextArchivedRequest(), 1);
    expect(state.nextActiveRequest(), 2);
    expect(state.activeRequest, 2);
    expect(state.archivedRequest, 1);
    expect(state.refreshEpoch, 0);
  });

  test('invalidates all markers or only active reads as requested', () {
    final state = CodexThreadRefreshState()
      ..nextActiveRequest()
      ..nextArchivedRequest();

    state.invalidateActive();
    expect(state.refreshEpoch, 0);
    expect(state.activeRequest, 2);
    expect(state.archivedRequest, 1);

    state.invalidateAll();
    expect(state.refreshEpoch, 1);
    expect(state.activeRequest, 3);
    expect(state.archivedRequest, 2);
  });
}
