import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

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

    expect(find.byKey(const Key('timeline-user-message-time')), findsNothing);
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
    expect(find.byKey(const Key('timeline-user-message-time')), findsNothing);
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
}
