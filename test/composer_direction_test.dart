import 'dart:async';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  testWidgets(
    'keeps a queued direction outside persisted entries and sends directly',
    (tester) async {
      final server = FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '应该是我图里的样子', prompt: '应该是我图里的样子'),
      );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump();

      final pendingMessage = find.byKey(const Key('pending-turn-steer'));
      final adjustDirection = find.byKey(const Key('adjust-direction-button'));
      final composerPanel = find.byKey(const Key('composer-panel'));
      expect(pendingMessage, findsOneWidget);
      expect(adjustDirection, findsOneWidget);
      expect(find.byKey(const Key('discard-direction-button')), findsOneWidget);
      expect(
        find.descendant(of: composerPanel, matching: pendingMessage),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(pendingMessage).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('composer-field'))).dy),
      );
      expect(
        tester.getCenter(adjustDirection).dx,
        greaterThan(tester.getCenter(pendingMessage).dx),
      );
      expect(find.byKey(const Key('adjust-direction-dialog')), findsNothing);
      await tester.tap(adjustDirection);
      await tester.pump();
      expect(server.steeredTurnPrompt, '应该是我图里的样子');
      expect(controller.pendingTurnSteer, isNull);
      expect(find.byKey(const Key('adjust-direction-dialog')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('does not queue an empty direction while a task is running', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.pendingTurnSteer, isNull);
    expect(find.byKey(const Key('pending-turn-steer')), findsNothing);
    expect(tester.widget<TextField>(field).enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('discards a queued direction from the composer header', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.queueTurnSteer(
      const PendingTurnSteer(displayText: '不要发送这条', prompt: '不要发送这条'),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('discard-direction-button')));
    await tester.pump();

    expect(controller.pendingTurnSteer, isNull);
    expect(find.byKey(const Key('pending-turn-steer')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'queues multiple directions and controls each row independently',
    (tester) async {
      final server = FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final field = find.byKey(const Key('composer-field'));
      for (final message in ['第一条调整', '第二条调整', '第三条调整']) {
        await tester.enterText(field, message);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
      }

      expect(controller.pendingTurnSteers.map((item) => item.displayText), [
        '第一条调整',
        '第二条调整',
        '第三条调整',
      ]);
      expect(find.text('调整方向'), findsNWidgets(3));
      await tester.tap(find.byKey(const Key('discard-direction-button-1')));
      await tester.pump();
      expect(controller.pendingTurnSteers.map((item) => item.displayText), [
        '第一条调整',
        '第三条调整',
      ]);
      await tester.tap(find.byKey(const Key('adjust-direction-button-1')));
      await tester.pump();
      expect(server.steeredTurnPrompt, '第三条调整');
      expect(controller.pendingTurnSteers.single.displayText, '第一条调整');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('bounds a long direction queue and disables parallel sends', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final steerCompleter = Completer<String>();
    final server = FakeCodexAppServer()..steerCompleter = steerCompleter;
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    for (var index = 0; index < 12; index++) {
      controller.queueTurnSteer(
        PendingTurnSteer(displayText: '方向 $index', prompt: '方向 $index'),
      );
    }
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final scroll = find.byKey(const Key('pending-turn-steer-scroll'));
    expect(scroll, findsOneWidget);
    expect(tester.getSize(scroll).height, lessThanOrEqualTo(220));
    expect(find.byKey(const Key('composer-field')), findsOneWidget);
    await tester.tap(find.byKey(const Key('adjust-direction-button')));
    await tester.pump();

    final secondSend = tester.widget<TextButton>(
      find.byKey(const Key('adjust-direction-button-1')),
    );
    expect(secondSend.onPressed, isNull);
    steerCompleter.complete('turn-2');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps the composer editable and accepts attachments while steering an active turn',
    (tester) async {
      const channel = MethodChannel('codex_desk/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => [
          {'path': '/tmp/steer.png', 'isDirectory': false},
          {'path': '/workspace/context.dart', 'isDirectory': false},
        ],
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final server = FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final field = find.byKey(const Key('composer-field'));
      expect(tester.widget<TextField>(field).enabled, isTrue);
      expect(
        tester
            .widget<PopupMenuButton<dynamic>>(
              find.byKey(const Key('composer-add-button')),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(field);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      // The live thinking indicator deliberately animates while a turn is
      // active, so settling is neither expected nor necessary here.
      await tester.pump();
      expect(
        find.byKey(const Key('composer-attachment-/tmp/steer.png')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('composer-attachment-/workspace/context.dart')),
        findsOneWidget,
      );
      await tester.enterText(field, '请改成灰色');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(server.steeredTurnPrompt, isNull);
      expect(controller.pendingTurnSteer?.displayText, '请改成灰色');
      expect(find.byKey(const Key('pending-turn-steer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('adjust-direction-button')));
      await tester.pump();
      expect(server.steeredTurnPrompt, contains('请改成灰色'));
      expect(
        server.steeredTurnPrompt,
        contains('附加路径：/workspace/context.dart'),
      );
      expect(server.steeredTurnAdditionalInput, [
        {'type': 'localImage', 'path': '/tmp/steer.png'},
        {
          'type': 'mention',
          'name': 'context.dart',
          'path': '/workspace/context.dart',
        },
      ]);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
