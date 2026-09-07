import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/services/codex_clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists and cancels a scheduled prompt', () async {
    final store = FakeRuntimeConfigurationStore();
    final now = DateTime(2030, 1, 2, 9);
    final controller = CodexController(
      runtimeConfigurationStore: store,
      clock: CodexClock(now: () => now),
    )..workspacePath = '/workspace';

    final scheduled = await controller.schedulePrompt(
      prompt: '检查测试结果',
      runAt: now.add(const Duration(hours: 1)),
    );

    expect(scheduled, isTrue);
    expect(controller.scheduledTasks, hasLength(1));
    expect(store.savedScheduledTasks, hasLength(1));
    await controller.cancelScheduledTask(controller.scheduledTasks.single.id);
    expect(controller.scheduledTasks, isEmpty);
    expect(store.savedScheduledTasks, isEmpty);
    controller.dispose();
  });

  test(
    'does not dispatch a scheduled prompt cancelled during project switch',
    () async {
      final first = await Directory.systemTemp.createTemp(
        'codex-desk-schedule-current-',
      );
      final second = await Directory.systemTemp.createTemp(
        'codex-desk-schedule-target-',
      );
      addTearDown(() => first.delete(recursive: true));
      addTearDown(() => second.delete(recursive: true));
      final server = DelayedStartRuntimeFakeServer()..running = true;
      final now = DateTime(2030, 1, 2, 9);
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        clock: CodexClock(now: () => now),
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = first.path
        ..status = RuntimeStatus.ready;

      expect(
        await controller.schedulePrompt(
          prompt: '这条任务已经取消，不能发送',
          runAt: now.add(const Duration(hours: 1)),
        ),
        isTrue,
      );
      final taskId = controller.scheduledTasks.single.id;
      controller.workspacePath = second.path;
      final dispatch = controller.dispatchScheduledTaskForTesting(taskId);
      await server.startEntered.future;
      await controller.cancelScheduledTask(taskId);
      server.allowStart.complete();
      await dispatch;

      expect(controller.scheduledTasks, isEmpty);
      expect(server.startedTurnPrompt, isNull);
      controller.dispose();
    },
  );
}
