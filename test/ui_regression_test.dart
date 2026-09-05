import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_tasks_dialog.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_fakes/fake_codex_app_server.dart';

Future<void> sendMetaShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings search opens the matching settings section', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('settings-search-field')),
      '历史',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('settings-archived-chats-page')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace exposes global task and settings shortcuts', (
    tester,
  ) async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '旧任务',
        createdAt: DateTime(2026),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('composer-field')));

    controller
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.notifyListeners();
    await tester.pump();
    await tester.enterText(find.byKey(const Key('composer-field')), '/');
    await tester.pump();
    expect(find.byKey(const Key('composer-slash-menu')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('composer-slash-menu')), findsNothing);
    expect(server.interruptedThreadId, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(server.interruptedThreadId, 'thread-1');
    expect(server.interruptedTurnId, 'turn-1');

    controller
      ..status = RuntimeStatus.ready
      ..activeThreadId = null
      ..activeTurnId = null;
    controller.notifyListeners();
    await tester.pump();

    await sendMetaShortcut(tester, LogicalKeyboardKey.keyK);
    expect(find.byKey(const Key('task-search-dialog')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await sendMetaShortcut(tester, LogicalKeyboardKey.keyN);
    expect(controller.entries, isEmpty);

    await sendMetaShortcut(tester, LogicalKeyboardKey.comma);
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
  });

  testWidgets('project menu keeps local history import and export entries', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final workspaceTile = find.byKey(
      const ValueKey('sidebar-workspace-/workspace'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(workspaceTile));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sidebar-workspace-more-/workspace')),
    );
    await tester.pumpAndSettle();

    expect(find.text('导出本地历史'), findsOneWidget);
    expect(find.text('导入到当前项目'), findsOneWidget);
  });

  testWidgets('scheduling a past time shows actionable validation', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduledTasksDialog(
            controller: controller,
            initialPrompt: '检查项目状态',
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('scheduled-task-time-picker')));
    await tester.pumpAndSettle();
    final today = DateTime.now().day.toString();
    await tester.tap(find.text(today).last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final timeFields = find.byType(TextField);
    await tester.enterText(timeFields.first, '12');
    await tester.enterText(timeFields.last, '00');
    final am = find.text('AM');
    if (am.evaluate().isNotEmpty) await tester.tap(am);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-task-confirm')));
    await tester.pump();

    expect(
      find.byKey(const Key('scheduled-task-validation-error')),
      findsOneWidget,
    );
    expect(find.textContaining('未来的执行时间'), findsOneWidget);
    expect(controller.scheduledTasks, isEmpty);
  });
}
