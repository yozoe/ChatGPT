import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_conversation_pane.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'widget_test_fakes.dart';

typedef _FakeRuntimeConfigurationStore = FakeRuntimeConfigurationStore;
typedef _MemoryConversationHistoryStore = MemoryConversationHistoryStore;

CodexThread threadForTest({
  required String id,
  String? modelProvider,
  String? model,
  String? status,
}) => CodexThread(
  id: id,
  preview: 'preview-$id',
  createdAt: 1,
  updatedAt: 2,
  modelProvider: modelProvider,
  model: model,
  status: status,
);

void main() {
  late _MemoryConversationHistoryStore historyStore;
  late _FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    historyStore = _MemoryConversationHistoryStore();
    runtimeConfigurationStore = _FakeRuntimeConfigurationStore();
    CodexController.testingConversationHistoryStore = historyStore;
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  testWidgets(
    'keeps variable-height timeline geometry stable during slow scrolling',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..replaceTimelineEntriesForTesting(
          List<TimelineEntry>.generate(
            96,
            (index) => TimelineEntry(
              kind: TimelineKind.agent,
              title: 'Codex',
              detail: '历史消息 $index\n${'内容 ' * (index % 8 + 1)}',
              createdAt: DateTime(2026, 1, 1, 0, 0, index),
            ),
          ),
        );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pumpAndSettle();

      final timeline = tester.widget<ListView>(
        find.descendant(
          of: find.byKey(
            const ValueKey('conversation-timeline-/workspace:draft'),
          ),
          matching: find.byType(ListView),
        ),
      );
      final position = timeline.controller!.position;
      final initialMaximum = position.maxScrollExtent;
      expect(initialMaximum, greaterThan(0));
      for (var offset = 0.0; offset < initialMaximum; offset += 18) {
        position.jumpTo(offset);
        await tester.pump();
        expect(position.maxScrollExtent, closeTo(initialMaximum, 0.1));
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'provider updates follow the latest item until the user scrolls up',
    (tester) async {
      final controller = CodexController(
        server: FakeCodexAppServer(),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      final initialEntries = List<TimelineEntry>.generate(
        30,
        (index) => TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '历史消息 $index\n${'内容 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 0, index),
        ),
      );
      controller.replaceTimelineEntriesForTesting(initialEntries);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            codexControllerProvider.overrideWith(
              () => InjectedCodexControllerNotifier(controller),
            ),
          ],
          child: const MaterialApp(home: CodexWorkspace()),
        ),
      );
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
      final timeline = tester.widget<ListView>(find.byType(ListView));
      expect(timeline.controller!.offset, 0);
      expect(timeline.controller!.position.maxScrollExtent, greaterThan(0));

      controller.replaceTimelineEntriesForTesting([
        ...initialEntries,
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '最新消息\n${'新内容 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 1),
        ),
      ]);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(timeline.controller!.position.extentAfter, lessThan(32));

      // A programmatic bottom correction also dispatches a scroll update.
      // It must not be mistaken for manual reading, or later reply updates
      // would remain below the viewport until the user scrolls again.
      controller.replaceTimelineEntriesForTesting([
        ...controller.entries,
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '连续到达的最新消息\n${'后续内容 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 1, 1),
        ),
      ]);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(timeline.controller!.position.extentAfter, lessThan(32));

      controller.replaceTimelineEntriesForTesting([
        ...controller.entries,
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '与上滑同一帧到达的状态更新',
          createdAt: DateTime(2026, 1, 1, 0, 2),
        ),
      ]);
      final timelineRect = tester.getRect(find.byType(ListView));
      final gesture = await tester.startGesture(
        Offset(timelineRect.left + 8, timelineRect.center.dy),
      );
      await gesture.moveBy(const Offset(0, 360));
      await tester.pump();
      await gesture.up();
      expect(timeline.controller!.position.extentAfter, greaterThan(48));
      final readingOffset = timeline.controller!.offset;

      // The provider update above already queued a post-frame scroll. It must
      // re-check the user's position instead of stealing the reading viewport.
      await tester.pump();
      await tester.pumpAndSettle();
      expect(timeline.controller!.offset, closeTo(readingOffset, 0.1));

      controller.replaceTimelineEntriesForTesting(controller.entries);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(timeline.controller!.offset, closeTo(readingOffset, 0.1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'does not snap back when leaving the bottom within the completion threshold',
    (tester) async {
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..activeThreadId = 'completed-thread'
        ..threads = [threadForTest(id: 'completed-thread')];
      controller.replaceTimelineEntriesForTesting(
        List<TimelineEntry>.generate(
          24,
          (index) => TimelineEntry(
            kind: TimelineKind.agent,
            title: 'Codex',
            detail: '可滚动内容 $index\n${'内容 ' * 10}',
            createdAt: DateTime(2026, 1, 1, 0, 0, index),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final timelineFinder = find.descendant(
        of: find.byKey(
          const ValueKey('conversation-timeline-/workspace:completed-thread'),
        ),
        matching: find.byType(ListView),
      );
      final timeline = tester.widget<ListView>(timelineFinder);
      timeline.controller!.jumpTo(
        timeline.controller!.position.maxScrollExtent,
      );
      await tester.pump();

      // The timeline remains within the 48px completion threshold, but this
      // gesture is explicitly toward older messages and must never queue a
      // stale jump back to the newest item.
      final timelineRect = tester.getRect(timelineFinder);
      final gesture = await tester.startGesture(
        Offset(timelineRect.left + 8, timelineRect.center.dy),
      );
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      final readingOffset = timeline.controller!.offset;
      expect(timeline.controller!.position.extentAfter, greaterThan(0));
      expect(timeline.controller!.position.extentAfter, lessThanOrEqualTo(48));

      await tester.pump();
      await tester.pump();
      expect(timeline.controller!.offset, closeTo(readingOffset, 0.1));
      await gesture.up();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'shows a scroll-to-bottom affordance after reading older messages',
    (tester) async {
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..replaceTimelineEntriesForTesting(
          List<TimelineEntry>.generate(
            30,
            (index) => TimelineEntry(
              kind: TimelineKind.agent,
              title: 'Codex',
              detail: '可滚动内容 $index\n${'内容 ' * 12}',
              createdAt: DateTime(2026, 1, 1, 0, 0, index),
            ),
          ),
        );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pumpAndSettle();

      final timelineFinder = find.descendant(
        of: find.byKey(
          const ValueKey('conversation-timeline-/workspace:draft'),
        ),
        matching: find.byType(ListView),
      );
      final timeline = tester.widget<ListView>(timelineFinder);
      timeline.controller!.jumpTo(
        timeline.controller!.position.maxScrollExtent,
      );
      await tester.pump();

      await tester.drag(timelineFinder, const Offset(0, 260));
      await tester.pumpAndSettle();

      final scrollToBottom = find.byKey(
        const Key('conversation-scroll-to-bottom-button'),
      );
      expect(scrollToBottom, findsOneWidget);
      expect(find.byTooltip('滚动到最新消息'), findsOneWidget);

      await tester.tap(scrollToBottom);
      await tester.pump(const Duration(milliseconds: 100));
      expect(timeline.controller!.position.extentAfter, greaterThan(1));

      // A user gesture that interrupts the return animation must keep its
      // reading position instead of being forced to the newest item.
      await tester.drag(timelineFinder, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(timeline.controller!.position.extentAfter, greaterThan(1));
      expect(scrollToBottom, findsOneWidget);

      await tester.tap(scrollToBottom);
      await tester.pumpAndSettle();

      expect(timeline.controller!.position.extentAfter, lessThan(1));
      expect(scrollToBottom, findsNothing);

      timeline.controller!.jumpTo(
        timeline.controller!.position.maxScrollExtent - 260,
      );
      await tester.pump();
      expect(scrollToBottom, findsOneWidget);

      await tester.tap(scrollToBottom);
      controller.replaceTimelineEntriesForTesting([
        ...controller.entries,
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '动画期间抵达的最新内容\n${'后续内容 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 1),
        ),
      ]);
      await tester.pumpAndSettle();

      controller.replaceTimelineEntriesForTesting([
        ...controller.entries,
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '动画结束后抵达的内容\n${'继续跟随 ' * 12}',
          createdAt: DateTime(2026, 1, 1, 0, 2),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(timeline.controller!.position.extentAfter, lessThan(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('opens a first-time history viewport at the latest message', (
    tester,
  ) async {
    final server = FakeCodexAppServer();
    final thread = threadForTest(id: 'long-history');
    server
      ..listResponse = [thread.toJson()]
      ..resumeResult = {
        'thread': {
          'turns': List<JsonMap>.generate(48, (index) {
            final answer = index == 47
                ? '最后一条历史回复'
                : '历史回复 $index\n${'较长的 Markdown 内容 ' * (index % 5 + 1)}';
            return {
              'id': 'turn-$index',
              'items': [
                {
                  'id': 'user-$index',
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': '历史问题 $index'},
                  ],
                },
                {'id': 'agent-$index', 'type': 'agentMessage', 'text': answer},
              ],
            };
          }),
        },
      };
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [thread];

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.text('preview-long-history'));
    await tester.pumpAndSettle();

    final timelineFinder = find.descendant(
      of: find.byKey(
        const ValueKey('conversation-timeline-/workspace:long-history'),
      ),
      matching: find.byType(ListView),
    );
    final timeline = tester.widget<ListView>(timelineFinder);
    expect(timeline.controller!.position.extentAfter, lessThan(1));
    expect(
      controller.entries.map((entry) => entry.detail),
      contains('最后一条历史回复'),
    );
    expect(find.byKey(const Key('thread-history-loading')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps a cached reading position when switching during history settling',
    (tester) async {
      JsonMap historyFor(String prefix) => {
        'thread': {
          'turns': List<JsonMap>.generate(48, (index) {
            return {
              'id': '$prefix-turn-$index',
              'items': [
                {
                  'id': '$prefix-user-$index',
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': '$prefix 问题 $index'},
                  ],
                },
                {
                  'id': '$prefix-agent-$index',
                  'type': 'agentMessage',
                  'text':
                      '$prefix 回复 $index\n${'高度不同的 Markdown 内容 ' * (index % 5 + 1)}',
                },
              ],
            };
          }),
        },
      };

      final server = FakeCodexAppServer();
      final first = threadForTest(id: 'cached-reading');
      final second = threadForTest(id: 'settling-history');
      server
        ..listResponse = [first.toJson(), second.toJson()]
        ..resumeResult = historyFor('第一会话');
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..threads = [first, second];

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.tap(find.text('preview-cached-reading'));
      await tester.pumpAndSettle();

      final firstTimelineFinder = find.descendant(
        of: find.byKey(
          const ValueKey('conversation-timeline-/workspace:cached-reading'),
        ),
        matching: find.byType(ListView),
      );
      final firstTimeline = tester.widget<ListView>(firstTimelineFinder);
      final firstScrollController = firstTimeline.controller!;
      final readingOffset =
          firstScrollController.position.maxScrollExtent - 160;
      firstScrollController.jumpTo(readingOffset);
      await tester.pump();
      expect(firstScrollController.offset, closeTo(readingOffset, 0.1));

      server.resumeResult = historyFor('第二会话');
      await tester.tap(find.text('preview-settling-history'));
      await tester.pump();

      expect(controller.activeThreadId, 'settling-history');
      expect(controller.isResumingThread, isFalse);
      expect(find.byKey(const Key('thread-history-loading')), findsOneWidget);
      final loadingSurface = find.byKey(const Key('thread-history-loading'));
      expect(
        tester.getSize(loadingSurface),
        tester.getSize(find.byType(ConversationPane)),
      );

      await tester.tap(find.text('preview-cached-reading'));
      await tester.pumpAndSettle();

      expect(controller.activeThreadId, 'cached-reading');
      expect(firstScrollController.offset, closeTo(readingOffset, 0.1));
      expect(find.byKey(const Key('thread-history-loading')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keeps completed Markdown subtrees stable during stream updates',
    (tester) async {
      final controller = CodexController(server: FakeCodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running;
      final completed = TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '**已完成的回复**',
        createdAt: DateTime(2026, 1, 1),
      );
      final streaming = TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '正在输出',
        createdAt: DateTime(2026, 1, 1, 0, 1),
      );
      controller.replaceTimelineEntriesForTesting([completed, streaming]);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      final completedEntry = find.byKey(
        ValueKey('timeline-entry-/workspace:draft-${completed.id}'),
      );
      final markdownFinder = find.descendant(
        of: completedEntry,
        matching: find.byType(MarkdownBody),
      );
      final before = tester.widget<MarkdownBody>(markdownFinder);

      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.system,
          title: '迟到的前置记录',
          detail: '',
          createdAt: DateTime(2025, 12, 31, 23, 59),
        ),
        completed,
        streaming.copyWith(detail: '正在输出更多文字'),
      ]);
      await tester.pump();

      final after = tester.widget<MarkdownBody>(markdownFinder);
      expect(identical(after, before), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
