import 'package:chatgpt/src/app_controller_runtime_connection.dart';
import 'package:chatgpt/src/app_controller_runtime_reconnect_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_fakes/managed_runtime_fake_server.dart';

void main() {
  test('delegates probe, lifecycle start, initialization, and stop', () async {
    final server = ManagedRuntimeFakeServer();
    final connection = CodexRuntimeConnection(server);

    final probe = await connection.probe();
    await connection.start(workingDirectory: '/tmp/codex-desk-test');
    await connection.initialize();
    await connection.stop();

    expect(probe.isAvailable, isTrue);
    expect(server.startCalls, 1);
    expect(server.runtimeDirectory, '/tmp/codex-desk-test');
    expect(server.stopCalls, 1);
    expect(server.isRunning, isFalse);
  });

  test('bounds reconnect attempts and cancels pending timers', () async {
    var disposed = false;
    var allowed = true;
    var reconnects = 0;
    final scheduled = <Duration>[];
    final coordinator = CodexRuntimeReconnectCoordinator(
      isDisposed: () => disposed,
      canSchedule: () => allowed,
      reconnect: () async => reconnects++,
      onScheduled: scheduled.add,
      delays: const [Duration.zero, Duration.zero],
    );

    coordinator.schedule();
    coordinator.schedule();
    expect(coordinator.isScheduled, isTrue);
    expect(scheduled, [Duration.zero]);
    await Future<void>.delayed(Duration.zero);
    expect(reconnects, 1);

    coordinator.schedule();
    await Future<void>.delayed(Duration.zero);
    expect(reconnects, 2);
    coordinator.schedule();
    expect(coordinator.isScheduled, isFalse);

    allowed = false;
    coordinator.schedule();
    expect(coordinator.isScheduled, isFalse);
    disposed = true;
    coordinator.dispose();
  });
}
