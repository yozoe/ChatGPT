import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_subagent_thread_state.dart';
import 'package:chatgpt/src/domain/subagent_thread_view.dart';

void main() {
  SubagentThreadView view(String id, {String status = 'working'}) =>
      SubagentThreadView(
        threadId: id,
        title: id,
        status: status,
        entries: const [],
      );

  test('keeps recently inspected views within the bounded cache', () {
    final state = CodexSubagentThreadState(maximumCacheEntries: 2);

    state.store(view('one'));
    state.store(view('two'));
    expect(state.view('one')?.threadId, 'one');
    state.store(view('three'));

    expect(state.peek('one')?.threadId, 'one');
    expect(state.peek('two'), isNull);
    expect(state.peek('three')?.threadId, 'three');
  });

  test('invalidates requests and working views when runtime changes', () {
    final state = CodexSubagentThreadState();

    state.store(view('one'));
    final request = state.beginRequest('one');
    expect(state.isCurrentRequest('one', request), isTrue);

    state.invalidateForRuntimeChange(
      error: 'runtime changed',
      workingStatus: 'working',
    );

    expect(state.isCurrentRequest('one', request), isFalse);
    expect(state.peek('one')?.status, 'stopped');
    expect(state.peek('one')?.loading, isFalse);
    expect(state.peek('one')?.error, 'runtime changed');
  });

  test('clear cancels pending refresh callbacks', () async {
    final state = CodexSubagentThreadState();
    var called = false;
    state.store(view('one'));
    state.scheduleRefresh('one', () => called = true);
    state.clear();

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(called, isFalse);
  });
}
