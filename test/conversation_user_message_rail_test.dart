import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_thread_viewport_key.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_conversation_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_pasted_text.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_timeline_page_data.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail_mark.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail_preview_position_delegate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounds the cached preview for very large pasted text', () {
    final text = '首行 ${List.filled(200000, 'x').join()}';
    final pastedText = ComposerPastedText(id: 1, text: text);

    expect(pastedText.previewLabel, startsWith('首行 '));
    expect(pastedText.previewLabel.runes.length, lessThanOrEqualTo(96));
    expect(pastedText.text, same(text));
  });

  test('conversation rail preview stays inside vertical viewport bounds', () {
    const viewport = Size(900, 600);
    const preview = Size(322, 132);
    const topAnchor = Rect.fromLTWH(0, 0, 28, 9);

    ConversationUserMessageRailPreviewPositionDelegate delegateFor(
      Rect anchor,
    ) => ConversationUserMessageRailPreviewPositionDelegate(
      anchor: anchor,
      preferredWidth: preview.width,
      maximumHeight: preview.height,
      gap: 14,
      viewportInset: 12,
    );

    Offset positionFor(Rect anchor) =>
        delegateFor(anchor).getPositionForChild(viewport, preview);

    expect(positionFor(topAnchor).dy, 12);
    expect(
      positionFor(const Rect.fromLTWH(0, 591, 28, 9)).dy,
      viewport.height - preview.height - 12,
    );
    expect(
      delegateFor(topAnchor).getConstraintsForChild(
        const BoxConstraints.tightFor(width: 900, height: 600),
      ),
      const BoxConstraints(minWidth: 322, maxWidth: 322, maxHeight: 132),
    );
    expect(
      delegateFor(topAnchor).getConstraintsForChild(
        const BoxConstraints.tightFor(width: 200, height: 100),
      ),
      const BoxConstraints(minWidth: 146, maxWidth: 146, maxHeight: 76),
    );
  });

  testWidgets('conversation rail tapers around the hovered user message', (
    tester,
  ) async {
    late StateSetter rebuildHost;
    var railOffset = 0.0;
    const longSingleParagraph =
        '这是一条没有手动换行的很长用户消息，用来确认预览不会只显示第一行，而是能够在紧凑卡片中继续换行并展示足够的上下文内容。';
    final messages = List.generate(
      7,
      (index) => TimelineEntry(
        id: 'hover-user-$index',
        kind: TimelineKind.user,
        title: 'You',
        detail: switch (index) {
          2 => longSingleParagraph,
          3 => '第一个问题要修复，扫码逻辑单独拆出来\n第一个问题已修复：\n- 新增独立的 Debug 扫码服务',
          _ => '用户消息 $index',
        },
        createdAt: DateTime(2026, 1, 1, 0, 0, index),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildHost = setState;
            return Transform.translate(
              offset: Offset(0, railOffset),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 28,
                  height: 180,
                  child: ConversationUserMessageRail(
                    messages: messages,
                    onMessageSelected: (_) async {},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    Finder marker(int index) => find.byKey(
      ValueKey('conversation-user-message-rail-mark-hover-user-$index'),
    );
    List<double> markerWidths() => List.generate(
      messages.length,
      (index) => tester.getSize(marker(index)).width,
    );

    expect(markerWidths().toSet(), {8.0});

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(100, 10));
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(
          const ValueKey('conversation-user-message-rail-hit-hover-user-3'),
        ),
      ),
    );
    await tester.pump();
    final preview = find.byKey(
      const ValueKey('conversation-user-message-rail-preview-hover-user-3'),
    );
    expect(preview, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));

    final hoveredWidths = markerWidths();
    expect(hoveredWidths[3], 28);
    expect(hoveredWidths[3], greaterThan(hoveredWidths[2]));
    expect(hoveredWidths[2], greaterThan(hoveredWidths[1]));
    expect(hoveredWidths[1], greaterThan(hoveredWidths[0]));
    expect(hoveredWidths[4], hoveredWidths[2]);
    expect(hoveredWidths[5], hoveredWidths[1]);
    expect(hoveredWidths[6], hoveredWidths[0]);
    expect(find.text('第一个问题要修复，扫码逻辑单独拆出来'), findsOneWidget);
    expect(find.textContaining('新增独立的 Debug 扫码服务'), findsOneWidget);
    final previewRect = tester.getRect(preview);
    final overlayRect = tester.getRect(find.byType(Overlay).first);
    final hoveredMarkerRect = tester.getRect(marker(3));
    expect(previewRect.left, greaterThan(hoveredMarkerRect.right));
    expect(previewRect.center.dy, closeTo(hoveredMarkerRect.center.dy, 0.1));
    expect(previewRect.top, greaterThanOrEqualTo(overlayRect.top + 12));
    expect(previewRect.bottom, lessThanOrEqualTo(overlayRect.bottom - 12));

    rebuildHost(() => railOffset = 2);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(preview, findsOneWidget);
    expect(
      tester.getRect(preview).center.dy,
      closeTo(tester.getRect(marker(3)).center.dy, 0.1),
    );

    await mouse.moveTo(
      tester.getCenter(
        find.byKey(
          const ValueKey('conversation-user-message-rail-hit-hover-user-2'),
        ),
      ),
    );
    await tester.pump();
    expect(preview, findsNothing);
    expect(
      find.byKey(
        const ValueKey('conversation-user-message-rail-preview-hover-user-2'),
      ),
      findsOneWidget,
    );
    final singleParagraphText = tester.widget<Text>(
      find.text(longSingleParagraph),
    );
    expect(singleParagraphText.maxLines, 4);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey(
                'conversation-user-message-rail-preview-hover-user-2',
              ),
            ),
          )
          .height,
      greaterThan(60),
    );

    final railRect = tester.getRect(
      find.byKey(const Key('conversation-user-message-rail')),
    );
    await mouse.moveTo(Offset(railRect.center.dx, railRect.top + 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(markerWidths().toSet(), {8.0});
    expect(preview, findsNothing);
    expect(
      find.byKey(
        const ValueKey('conversation-user-message-rail-preview-hover-user-2'),
      ),
      findsNothing,
    );

    await mouse.moveTo(
      tester.getCenter(
        find.byKey(
          const ValueKey('conversation-user-message-rail-hit-hover-user-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(
        const ValueKey('conversation-user-message-rail-preview-hover-user-1'),
      ),
      findsNothing,
    );
  });

  testWidgets('conversation rail stays fixed and locates a user message', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final entries = [
      TimelineEntry(
        id: 'user-one',
        kind: TimelineKind.user,
        title: 'You',
        detail: '第一条用户消息',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        id: 'agent-one',
        kind: TimelineKind.agent,
        title: 'Assistant',
        detail: List.generate(
          400,
          (index) => '这条助手回复不应生成标记 $index',
        ).join('\n\n'),
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
      TimelineEntry(
        id: 'user-two',
        kind: TimelineKind.user,
        title: 'You',
        detail: '第二条用户消息\n有两行',
        createdAt: DateTime(2026, 1, 1, 0, 0, 2),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 240,
          child: ConversationTimeline(
            pageKey: const ThreadViewportKey(
              workspace: null,
              threadId: 'rail-test',
            ),
            data: TimelinePageData(
              entries: entries,
              fileChanges: const [],
              turnFileChanges: const [],
              turnDiff: null,
              showFileChangeSummary: false,
              activeActivity: null,
              activeCollaborationActivities: const [],
              streamingAgentEntryId: null,
              activeTurnStartedAt: null,
              isThinking: false,
            ),
            scrollController: controller,
            bottomPadding: 12,
            active: true,
            fileChangeSummaryExpanded: false,
            onFileChangeSummaryExpandedChanged: (_) {},
            activityExpanded: (_) => false,
            onMetricsChanged: (_) {},
            onUserScrollDirection: (_, _) {},
            onActivityExpandedChanged: (_, _) {},
            onReview: () async {},
            onUndo: () async {},
            canUndo: false,
            undoRunning: false,
            onOpenSubagent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final firstMarker = find.byKey(
      const ValueKey('conversation-user-message-rail-mark-user-one'),
    );
    expect(find.byType(ConversationUserMessageRailMark), findsNWidgets(2));
    expect(
      find.byKey(
        const ValueKey('conversation-user-message-rail-mark-user-one'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('conversation-user-message-rail-mark-user-two'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('conversation-user-message-rail-mark-agent-one'),
      ),
      findsNothing,
    );
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final markerPositionBeforeScroll = tester.getTopLeft(firstMarker);
    final maximumOffset = controller.position.maxScrollExtent;
    controller.jumpTo(maximumOffset);
    await tester.pump();
    expect(tester.getTopLeft(firstMarker), markerPositionBeforeScroll);
    expect(
      find.byKey(
        const ValueKey('timeline-entry-no-workspace:rail-test-user-one'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('conversation-user-message-rail-hit-user-one')),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(maximumOffset));
    final targetPosition = tester.getTopLeft(
      find.byKey(
        const ValueKey('timeline-entry-no-workspace:rail-test-user-one'),
      ),
    );
    expect(targetPosition.dy, greaterThanOrEqualTo(0));
    expect(targetPosition.dy, lessThan(240));
  });
}
