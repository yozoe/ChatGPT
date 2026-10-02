import 'dart:async';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_user_message_bubble.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

TimelineEntry goalMessage(String detail, {String id = 'goal-message'}) =>
    TimelineEntry(
      id: id,
      kind: TimelineKind.user,
      title: '你',
      detail: detail,
      createdAt: DateTime(2026, 8, 25, 8, 53),
    );

Future<TestGesture> hoverUserMessage(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.moveTo(
    tester.getCenter(
      find.byKey(const Key('timeline-user-message-hover-region')),
    ),
  );
  await tester.pump();
  return mouse;
}

void main() {
  testWidgets(
    'keeps user bubbles right aligned with left-aligned wrapped text',
    (tester) async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace';
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: '修复',
          createdAt: DateTime(2026),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final message = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('timeline-user-message')),
          matching: find.text('修复'),
        ),
      );
      expect(message.textAlign, isNull);
      final bubble = tester.getRect(
        find.byKey(const Key('timeline-user-message')),
      );
      expect(bubble.right, closeTo(776, 1));
      expect(
        find.byKey(const Key('timeline-user-message-disclosure')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('collapses and expands long user messages', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longMessage = List.generate(
      180,
      (index) => '第 $index 段很长的消息内容',
    ).join(' ');
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace';
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: longMessage,
        createdAt: DateTime(2026),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final messageFinder = find.byKey(const Key('timeline-user-message-text'));
    final disclosureFinder = find.byKey(
      const Key('timeline-user-message-disclosure'),
    );
    expect(disclosureFinder, findsOneWidget);
    expect(find.text('显示更多'), findsOneWidget);
    expect(tester.widget<Text>(messageFinder).maxLines, 16);
    expect(tester.widget<Text>(messageFinder).overflow, TextOverflow.ellipsis);
    final collapsedHeight = tester
        .getSize(find.byKey(const Key('timeline-user-message')))
        .height;

    await tester.tap(disclosureFinder);
    await tester.pump();

    expect(find.text('显示较少'), findsOneWidget);
    expect(tester.widget<Text>(messageFinder).maxLines, isNull);
    expect(
      tester.getSize(find.byKey(const Key('timeline-user-message'))).height,
      greaterThan(collapsedHeight),
    );

    tester.widget<TextButton>(disclosureFinder).onPressed!();
    await tester.pump();

    expect(find.text('显示更多'), findsOneWidget);
    expect(tester.widget<Text>(messageFinder).maxLines, 16);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows user-message actions only while its bubble is hovered', (
    tester,
  ) async {
    var copiedText = '';
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text']! as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace';
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: 'review代码',
        createdAt: DateTime(2026, 8, 25, 8, 53),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '后续回复保持原位。',
        createdAt: DateTime(2026, 8, 25, 8, 54),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(
      find.byKey(const Key('timeline-user-message-time')).hitTestable(),
      findsNothing,
    );
    final hoverRegion = find.byKey(
      const Key('timeline-user-message-hover-region'),
    );
    final initialHoverRegion = tester.getRect(hoverRegion);
    final followingReply = find.text('后续回复保持原位。');
    final initialFollowingReplyY = tester.getTopLeft(followingReply).dy;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(
      Offset(initialHoverRegion.center.dx, initialHoverRegion.bottom - 0.5),
    );
    await tester.pump();
    expect(find.byKey(const Key('timeline-user-message-time')), findsOneWidget);
    expect(find.text('8:53'), findsOneWidget);
    expect(find.byTooltip('复制消息'), findsOneWidget);
    expect(find.byTooltip('修改消息'), findsOneWidget);
    await tester.tap(find.byTooltip('复制消息'));
    await tester.pump();
    expect(copiedText, 'review代码');
    expect(tester.getRect(hoverRegion), initialHoverRegion);
    expect(tester.getTopLeft(followingReply).dy, initialFollowingReplyY);
    await tester.pump();
    expect(find.byKey(const Key('timeline-user-message-time')), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(
      find.byKey(const Key('timeline-user-message-time')).hitTestable(),
      findsNothing,
    );
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('timeline-user-message'))),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits a hovered user message inline and sends it', (
    tester,
  ) async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: '原始请求',
        createdAt: DateTime(2026, 8, 25, 8, 53),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final hoverRegion = find.byKey(
      const Key('timeline-user-message-hover-region'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(hoverRegion));
    await tester.pump();
    await tester.tap(find.byTooltip('修改消息'));
    await tester.pump();
    expect(
      find.byKey(const Key('timeline-user-message-editor')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('timeline-user-message-editor-field')),
          )
          .controller!
          .text,
      '原始请求',
    );

    await tester.enterText(
      find.byKey(const Key('timeline-user-message-editor-field')),
      '修订后的请求',
    );
    final sendButton = find.byKey(const Key('timeline-user-message-edit-send'));
    expect(tester.widget<FilledButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    for (var index = 0; index < 5; index++) {
      await tester.pump();
    }

    expect(controller.entries.map((entry) => entry.detail), contains('修订后的请求'));
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows a set-goal label only when the message row is wide', (
    tester,
  ) async {
    final entry = goalMessage('短');

    Widget buildBubble(double width) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: width,
            child: UserMessageBubble(
              entry: entry,
              onSubmitEdit: (_, _) async => true,
              onSetGoal: (_) async => true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildBubble(600));
    final mouse = await hoverUserMessage(tester);
    expect(find.text('设为目标'), findsOneWidget);
    expect(find.byTooltip('设为目标'), findsOneWidget);
    final wideButton = tester.getRect(
      find.byKey(const ValueKey('timeline-user-message-set-goal-goal-message')),
    );
    expect(wideButton.height, greaterThanOrEqualTo(22));

    await tester.pumpWidget(buildBubble(320));
    await tester.pump();
    expect(find.text('设为目标'), findsNothing);
    expect(find.byTooltip('设为目标'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('keeps all message actions inside an extremely narrow row', (
    tester,
  ) async {
    final entry = goalMessage('窄');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 96,
              child: UserMessageBubble(
                entry: entry,
                onSubmitEdit: (_, _) async => true,
                onSetGoal: (_) async => true,
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await hoverUserMessage(tester);
    final bubble = tester.getRect(
      find.byKey(const Key('timeline-user-message-hover-region')),
    );
    final actions = tester.getRect(
      find.byKey(const Key('timeline-user-message-actions')),
    );
    expect(actions.left, greaterThanOrEqualTo(bubble.left));
    expect(actions.right, lessThanOrEqualTo(bubble.right));
    expect(find.byTooltip('复制消息'), findsOneWidget);
    expect(find.byTooltip('修改消息'), findsOneWidget);
    expect(find.byTooltip('设为目标'), findsOneWidget);
    expect(find.byKey(const Key('timeline-user-message-time')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets('locks repeated set-goal clicks while the request is pending', (
    tester,
  ) async {
    final server = FakeCodexAppServer();
    final pending = Completer<JsonMap?>();
    server.setThreadGoalCompleter = pending;
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'goal-thread';
    controller.replaceTimelineEntriesForTesting([goalMessage('持续目标')]);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final mouse = await hoverUserMessage(tester);
    final button = find.byKey(
      const ValueKey('timeline-user-message-set-goal-goal-message'),
    );
    await tester.tap(button);
    await tester.pump();
    expect(server.setThreadGoalCalls, 1);
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    await tester.tap(button);
    await tester.pump();
    expect(server.setThreadGoalCalls, 1);

    pending.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    await mouse.removePointer();
  });

  testWidgets('shows set-goal request and length errors in the active thread', (
    tester,
  ) async {
    final server = FakeCodexAppServer()
      ..setThreadGoalError = StateError('goal write failed');
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'goal-thread';
    controller.replaceTimelineEntriesForTesting([goalMessage('持续目标')]);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    var mouse = await hoverUserMessage(tester);
    await tester.tap(find.byTooltip('设为目标'));
    await tester.pumpAndSettle();
    expect(find.textContaining('goal write failed'), findsOneWidget);
    expect(controller.lastError, isNull);

    server.setThreadGoalError = null;
    controller.replaceTimelineEntriesForTesting([
      goalMessage(List.filled(4001, '目').join(), id: 'long-goal-message'),
    ]);
    await tester.pump();
    await mouse.removePointer();
    mouse = await hoverUserMessage(tester);
    await tester.tap(find.byTooltip('设为目标'));
    await tester.pumpAndSettle();
    expect(find.textContaining('目标不能超过 4000 个字符'), findsOneWidget);
    expect(server.setThreadGoalCalls, 1);
    expect(controller.lastError, isNull);
    await mouse.removePointer();
  });

  testWidgets('shows goal and unrelated runtime errors independently', (
    tester,
  ) async {
    final server = FakeCodexAppServer()
      ..setThreadGoalError = StateError('goal write failed');
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'goal-thread'
      ..lastError = '已有运行时错误';
    controller.replaceTimelineEntriesForTesting([goalMessage('持续目标')]);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final mouse = await hoverUserMessage(tester);
    await tester.tap(find.byTooltip('设为目标'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-error-banner')), findsOneWidget);
    expect(
      find.byKey(const Key('conversation-goal-error-banner')),
      findsOneWidget,
    );
    expect(find.text('已有运行时错误'), findsOneWidget);
    expect(find.textContaining('goal write failed'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('isolates a delayed set-goal failure after switching threads', (
    tester,
  ) async {
    final server = FakeCodexAppServer();
    final pending = Completer<JsonMap?>();
    server.setThreadGoalCompleter = pending;
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'goal-a';
    controller.replaceTimelineEntriesForTesting([
      goalMessage('目标 A', id: 'goal-a-message'),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final mouse = await hoverUserMessage(tester);
    await tester.tap(find.byTooltip('设为目标'));
    await tester.pump();
    controller.activeThreadId = 'goal-b';
    controller.replaceTimelineEntriesForTesting([
      goalMessage('目标 B', id: 'goal-b-message'),
    ]);
    pending.completeError(StateError('目标 A 更新失败'));
    await tester.pumpAndSettle();

    expect(find.textContaining('目标 A 更新失败'), findsNothing);
    expect(controller.goalOperationError, isNull);
    controller.activeThreadId = 'goal-a';
    controller.replaceTimelineEntriesForTesting([
      goalMessage('目标 A', id: 'goal-a-message-restored'),
    ]);
    await tester.pump();
    expect(find.textContaining('目标 A 更新失败'), findsOneWidget);
    await mouse.removePointer();
  });
}
