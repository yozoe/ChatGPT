import 'dart:async';

import 'package:chatgpt/src/app_controller_workspace_operation_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes operations and continues after an older failure', () async {
    final coordinator = CodexWorkspaceOperationCoordinator();
    final firstGate = Completer<void>();
    final events = <String>[];

    final first = coordinator.serialize<void>(() async {
      events.add('first-start');
      await firstGate.future;
      events.add('first-fail');
      throw StateError('failed');
    });
    final second = coordinator.serialize<void>(() async {
      events.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);
    firstGate.complete();
    await expectLater(first, throwsStateError);
    await second;
    expect(events, ['first-start', 'first-fail', 'second']);
  });

  test('only runs the latest queued selection request', () async {
    final coordinator = CodexWorkspaceOperationCoordinator();
    final firstGate = Completer<void>();
    final events = <String>[];

    final first = coordinator.runLatest<bool>(
      staleValue: false,
      action: (isCurrent) async {
        events.add('first-start');
        await firstGate.future;
        events.add(isCurrent() ? 'first-current' : 'first-stale');
        return isCurrent();
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);
    final second = coordinator.runLatest<bool>(
      staleValue: false,
      action: (_) async {
        events.add('second');
        return true;
      },
    );
    final latest = coordinator.runLatest<bool>(
      staleValue: false,
      action: (isCurrent) async {
        events.add('latest');
        return isCurrent();
      },
    );

    firstGate.complete();
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(await latest, isTrue);
    expect(events, ['first-start', 'first-stale', 'latest']);
  });

  test('dispose invalidates a selection that is awaiting work', () async {
    final coordinator = CodexWorkspaceOperationCoordinator();
    final gate = Completer<void>();

    final selection = coordinator.runLatest<bool>(
      staleValue: false,
      action: (isCurrent) async {
        await gate.future;
        return isCurrent();
      },
    );

    coordinator.dispose();
    gate.complete();
    expect(await selection, isFalse);
    await coordinator.waitForIdle();
  });
}
