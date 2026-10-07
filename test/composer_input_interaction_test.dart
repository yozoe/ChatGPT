import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  testWidgets('does not send a composing IME value when Enter is pressed', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('composer-field')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'nihao',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .value
          .composing,
      const TextRange(start: 0, end: 5),
    );
    final entryCount = controller.entries.length;

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.entries, hasLength(entryCount));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-field')))
          .controller!
          .text,
      'nihao',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'does not send the Enter that has just confirmed an IME candidate',
    (tester) async {
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      await tester.tap(find.byKey(const Key('composer-field')));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'nihao',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pump();
      final entryCount = controller.entries.length;

      // Some macOS IMEs clear `composing` before dispatching the same Enter
      // that confirms the selected candidate.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你好',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(controller.entries, hasLength(entryCount));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('composer-field')))
            .controller!
            .text,
        '你好',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('sends after an IME composition was already confirmed', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('composer-field')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'nihao',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你好',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final entryCount = controller.entries.length;

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.entries, hasLength(entryCount + 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uses compact text and a circular send button in the composer', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final sendButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '发送任务',
      ),
    );
    expect(
      sendButton.style?.shape?.resolve(const <WidgetState>{}),
      isA<CircleBorder>(),
    );
    expect(
      sendButton.style?.fixedSize?.resolve(const <WidgetState>{}),
      const Size.square(36),
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('composer-field'))).style,
      isA<TextStyle>().having((style) => style.fontSize, 'fontSize', 13),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uses a circular stop button while a task is running', (
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

    final stopButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '停止当前任务',
      ),
    );
    expect(
      stopButton.style?.shape?.resolve(const <WidgetState>{}),
      isA<CircleBorder>(),
    );
    expect(
      stopButton.style?.fixedSize?.resolve(const <WidgetState>{}),
      const Size.square(36),
    );

    await tester.pumpWidget(const SizedBox());
  });
}
