import 'dart:async';
import 'dart:io';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_thinking_row.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

typedef _FakeRuntimeConfigurationStore = FakeRuntimeConfigurationStore;

void main() {
  test('updates one visible subagent activity through its lifecycle', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    void complete(JsonMap item) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/completed',
          params: {'threadId': 'thread-1', 'turnId': 'turn-1', 'item': item},
        ),
      );
    }

    complete({
      'id': 'spawn-1',
      'type': 'collabToolCall',
      'tool': 'spawnAgent',
      'status': 'completed',
      'newThreadId': 'review-thread',
      'agentStatus': {'name': 'Independent review', 'status': 'running'},
    });

    var activity = controller.entries.singleWhere(
      (entry) => entry.kind == TimelineKind.activity,
    );
    expect(activity.title, 'Independent review');
    expect(activity.detail, '已开始工作');
    expect(activity.activityKind, 'collaboration');
    expect(activity.activityStatus, 'working');

    complete({
      'id': 'wait-1',
      'type': 'collabToolCall',
      'tool': 'waitAgent',
      'status': 'completed',
      'receiverThreadId': 'review-thread',
      'agentStatus': {'status': 'completed'},
    });

    expect(
      controller.entries.where((entry) => entry.kind == TimelineKind.activity),
      hasLength(1),
    );
    activity = controller.entries.singleWhere(
      (entry) => entry.kind == TimelineKind.activity,
    );
    expect(activity.title, 'Independent review');
    expect(activity.detail, '已完成');
    expect(activity.activityStatus, 'completed');
    controller.dispose();
  });

  test(
    'shows plan, collaboration, compaction, and unknown live activities',
    () {
      final controller = CodexController(server: CodexAppServer())
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';

      void start(String id, String type, [JsonMap extra = const {}]) {
        controller.handleServerEventForTesting(
          ServerEvent(
            method: 'item/started',
            params: {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {'id': id, 'type': type, ...extra},
            },
          ),
        );
      }

      start('plan-1', 'plan');
      expect(controller.activeLiveActivity?.label, '正在整理计划');
      start('collab-1', 'collabToolCall', {'tool': 'spawnAgent'});
      expect(controller.activeLiveActivity?.label, 'Independent task');
      expect(controller.activeLiveActivity?.detail, '已开始工作');
      start('compact-1', 'contextCompaction');
      expect(controller.activeLiveActivity?.label, '正在压缩对话上下文');
      start('future-1', 'futureOperation', {'internal': 'do not expose'});
      expect(controller.activeLiveActivity?.label, '正在执行操作');
      expect(controller.activeLiveActivity?.detail, isEmpty);
      start('user-1', 'userMessage');
      expect(controller.activeLiveActivity?.itemId, 'future-1');
      controller.dispose();
    },
  );

  test('distinguishes web search action activities', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    void start(String id, JsonMap action) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/started',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {'id': id, 'type': 'webSearch', 'action': action},
          },
        ),
      );
    }

    start('search-1', {'type': 'search', 'query': 'Codex'});
    expect(controller.activeLiveActivity?.label, '正在搜索网页');
    expect(controller.activeLiveActivity?.detail, 'Codex');
    start('open-1', {'type': 'openPage', 'url': 'https://example.com'});
    expect(controller.activeLiveActivity?.label, '正在打开网页');
    expect(controller.activeLiveActivity?.detail, 'https://example.com');
    start('find-1', {'type': 'findInPage', 'pattern': 'ThreadItem'});
    expect(controller.activeLiveActivity?.label, '正在页内查找');
    expect(controller.activeLiveActivity?.detail, 'ThreadItem');
    controller.dispose();
  });

  testWidgets('renders the quiet live command row and completed duration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'turn': {'id': 'turn-1'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'command-1',
            'type': 'commandExecution',
            'command': '/bin/zsh -lc dart test',
          },
        },
      ),
    );
    await tester.pump();

    expect(controller.activeTurnStartedAt, isNotNull);

    expect(find.byKey(const Key('live-command-row')), findsOneWidget);
    expect(find.byKey(const Key('live-command-shimmer')), findsOneWidget);
    expect(find.byKey(const Key('live-thinking-row')), findsNothing);
    expect(find.byKey(const Key('live-elapsed-row')), findsOneWidget);
    expect(find.byKey(const Key('live-elapsed-divider')), findsOneWidget);
    final timeline = find.byKey(
      const PageStorageKey<String>(
        'conversation-timeline-no-workspace:thread-1',
      ),
    );
    expect(timeline, findsOneWidget);
    expect(
      find.descendant(of: timeline, matching: find.byType(Divider)),
      findsOneWidget,
    );
    expect(find.text('已处理 0 秒'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('live-elapsed-row')))
          .properties
          .liveRegion,
      isNot(isTrue),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已处理 1 秒'), findsOneWidget);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'command-1',
            'type': 'commandExecution',
            'command': '/bin/zsh -lc dart test',
          },
        },
      ),
    );
    await tester.pump();

    expect(controller.status, RuntimeStatus.running);
    expect(controller.activeLiveActivity, isNull);
    expect(find.byKey(const Key('live-command-row')), findsNothing);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'thread-1',
          'turn': {'id': 'turn-1', 'status': 'completed', 'durationMs': 63000},
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('live-command-row')), findsNothing);
    expect(find.byKey(const Key('live-thinking-row')), findsNothing);
    expect(find.text('耗时 1 分钟 3 秒'), findsOneWidget);
    expect(find.text('已运行了命令'), findsOneWidget);
    expect(find.text('已运行 /bin/zsh -lc dart test'), findsNothing);

    await tester.tap(find.text('已运行了命令'));
    await tester.pump();

    expect(find.text('已运行 /bin/zsh -lc dart test'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('keeps streaming agent identity across overlapping live activities', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-overlap';
    addTearDown(controller.dispose);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'threadId': 'thread-overlap',
          'turn': {'id': 'turn-overlap'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {
          'threadId': 'thread-overlap',
          'turnId': 'turn-overlap',
          'itemId': 'agent-overlap',
          'delta': '仍在输出',
        },
      ),
    );
    final streamingEntryId = controller.activeStreamingAgentEntryId;
    expect(streamingEntryId, isNotNull);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-overlap',
          'turnId': 'turn-overlap',
          'item': {
            'id': 'command-overlap',
            'type': 'commandExecution',
            'command': 'flutter test',
          },
        },
      ),
    );

    expect(controller.activeLiveActivity?.kind, 'commandExecution');
    expect(controller.activeStreamingAgentEntryId, streamingEntryId);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-overlap',
          'turnId': 'turn-overlap',
          'item': {'id': 'agent-overlap', 'type': 'agentMessage'},
        },
      ),
    );

    expect(controller.activeStreamingAgentEntryId, isNull);
    expect(controller.activeLiveActivity?.itemId, 'command-overlap');
  });

  testWidgets(
    'keeps processed time above the active reply and after older replies',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: CodexAppServer())
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..replaceTimelineEntriesForTesting([
          TimelineEntry(
            kind: TimelineKind.agent,
            title: 'Codex',
            detail: '上一轮回复',
            createdAt: DateTime(2026),
          ),
          TimelineEntry(
            kind: TimelineKind.user,
            title: '你',
            detail: '修复',
            createdAt: DateTime.now(),
          ),
        ]);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'thread-1',
            'turn': {'id': 'turn-1'},
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final elapsed = find.byKey(const Key('live-elapsed-row'));
      expect(
        tester.getTopLeft(find.text('修复')).dy,
        lessThan(tester.getTopLeft(elapsed).dy),
      );

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/started',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {'id': 'active-reply', 'type': 'agentMessage'},
          },
        ),
      );
      await tester.pump();
      expect(find.text('正在撰写回复'), findsOneWidget);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'active-reply',
            'delta': '当前流式回复',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      final previousReplyTop = tester.getTopLeft(find.text('上一轮回复')).dy;
      final userPromptTop = tester.getTopLeft(find.text('修复')).dy;
      final elapsedTop = tester.getTopLeft(elapsed).dy;
      final activeReplyTop = tester.getTopLeft(find.text('当前流式回复')).dy;
      expect(previousReplyTop, lessThan(userPromptTop));
      expect(userPromptTop, lessThan(elapsedTop));
      expect(elapsedTop, lessThan(activeReplyTop));
      expect(find.text('正在撰写回复'), findsNothing);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {'id': 'active-reply', 'type': 'agentMessage'},
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/started',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'active-command',
              'type': 'commandExecution',
              'command': 'flutter test',
            },
          },
        ),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(elapsed).dy,
        lessThan(tester.getTopLeft(find.text('当前流式回复')).dy),
      );
      expect(
        tester.getTopLeft(find.text('当前流式回复')).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('live-command-row'))).dy,
        ),
      );

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('uses elapsed time as the header above expanded task details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: '请完成任务',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '任务已创建',
        detail: 'Thread thread-1',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '我先检查项目。',
        agentPhase: 'commentary',
        createdAt: DateTime(2026, 1, 1, 0, 0, 2),
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'flutter analyze\nNo issues found',
        createdAt: DateTime(2026, 1, 1, 0, 0, 3),
      ),
      TimelineEntry(
        kind: TimelineKind.approval,
        title: '已批准命令',
        detail: 'flutter analyze',
        createdAt: DateTime(2026, 1, 1, 0, 0, 4),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '任务已经完成。',
        agentPhase: 'final_answer',
        createdAt: DateTime(2026, 1, 1, 0, 0, 5),
      ),
      TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 4 秒',
        detail: '',
        createdAt: DateTime(2026, 1, 1, 0, 0, 6),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '任务完成',
        detail: '',
        createdAt: DateTime(2026, 1, 1, 0, 0, 7),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.text('已运行了命令'), findsOneWidget);
    expect(find.text('已运行 flutter analyze'), findsNothing);
    expect(find.text('No issues found'), findsNothing);
    expect(
      tester.getTopLeft(find.text('耗时 4 秒')).dy,
      lessThan(tester.getTopLeft(find.text('任务已创建')).dy),
    );
    expect(
      tester.getTopLeft(find.text('任务已创建')).dy,
      lessThan(tester.getTopLeft(find.text('我先检查项目。')).dy),
    );
    expect(
      tester.getTopLeft(find.text('我先检查项目。')).dy,
      lessThan(tester.getTopLeft(find.text('已运行了命令')).dy),
    );
    expect(
      tester.getTopLeft(find.text('已运行了命令')).dy,
      lessThan(tester.getTopLeft(find.text('任务已经完成。')).dy),
    );
    expect(
      tester.getTopLeft(find.text('任务已经完成。')).dy,
      lessThan(tester.getTopLeft(find.text('任务完成')).dy),
    );
    final elapsedToggle = find.byKey(
      const Key('completed-turn-disclosure-toggle'),
    );
    expect(
      find.descendant(of: elapsedToggle, matching: find.byType(Container)),
      findsNothing,
    );
    expect(
      find.byKey(const Key('completed-turn-disclosure-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('completed-turn-disclosure-divider')),
      findsOneWidget,
    );
    expect(find.byType(AnimatedSize), findsAtLeastNWidgets(1));

    await tester.tap(find.text('已运行了命令'));
    await tester.pump();

    expect(find.text('已运行 flutter analyze'), findsOneWidget);

    await tester.tap(find.text('已运行了命令'));
    await tester.pump();

    expect(find.text('已运行 flutter analyze'), findsNothing);

    await tester.tap(elapsedToggle);
    await tester.pump();

    final expandedDividerY = tester
        .getTopLeft(find.byKey(const Key('completed-turn-disclosure-divider')))
        .dy;
    await tester.pump(const Duration(milliseconds: 90));
    final animatingDividerY = tester
        .getTopLeft(find.byKey(const Key('completed-turn-disclosure-divider')))
        .dy;
    expect(animatingDividerY, lessThan(expandedDividerY));
    await tester.pumpAndSettle();
    final collapsedDividerY = tester
        .getTopLeft(find.byKey(const Key('completed-turn-disclosure-divider')))
        .dy;
    expect(collapsedDividerY, lessThan(animatingDividerY));
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: elapsedToggle,
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0,
    );
    expect(find.text('已运行 flutter analyze'), findsNothing);
    expect(find.text('已批准命令'), findsOneWidget);
    expect(find.text('任务已经完成。'), findsOneWidget);
    expect(
      find.byKey(const Key('completed-turn-disclosure-divider')),
      findsOneWidget,
    );

    await tester.tap(elapsedToggle);
    await tester.pump();

    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: elapsedToggle,
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0.25,
    );
    await tester.pump(const Duration(milliseconds: 90));
    final reopeningDividerY = tester
        .getTopLeft(find.byKey(const Key('completed-turn-disclosure-divider')))
        .dy;
    expect(reopeningDividerY, greaterThan(collapsedDividerY));
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(
            find.byKey(const Key('completed-turn-disclosure-divider')),
          )
          .dy,
      greaterThan(reopeningDividerY),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'renders agent replies without a Codex label and keeps plain duration',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = CodexController(server: CodexAppServer());
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: '请直接回答',
          createdAt: DateTime(2026),
        ),
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '这是直接回答。',
          createdAt: DateTime(2026, 1, 1, 0, 0, 1),
        ),
        TimelineEntry(
          kind: TimelineKind.elapsed,
          title: '耗时 1 秒',
          detail: '',
          createdAt: DateTime(2026, 1, 1, 0, 0, 2),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(find.text('Codex'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Codex 回复')), findsOneWidget);
      expect(find.text('这是直接回答。'), findsOneWidget);
      expect(find.text('耗时 1 秒'), findsOneWidget);
      expect(
        find.byKey(const Key('completed-turn-disclosure-toggle')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets('labels post-command waiting feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: const LiveThinkingRow(label: '正在整理命令结果')),
    );

    expect(find.text('正在整理命令结果'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('animates the centered thinking dots as a wave', (tester) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1'
      ..replaceTimelineEntriesForTesting(
        List<TimelineEntry>.generate(
          18,
          (index) => TimelineEntry(
            kind: TimelineKind.agent,
            title: 'Codex',
            detail: '用于滚动定位的历史回复 $index\n${'内容 ' * 10}',
            createdAt: DateTime(2026, 1, 1, 0, 0, index),
          ),
        ),
      );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'thread/goal/updated',
        params: {
          'threadId': 'thread-1',
          'goal': {
            'threadId': 'thread-1',
            'objective': '完成当前目标',
            'status': 'active',
          },
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();

    expect(find.byKey(const Key('live-thinking-loader')), findsOneWidget);
    expect(find.byKey(const Key('composer-activity-pill')), findsNothing);
    expect(find.text('正在处理任务'), findsNothing);
    expect(find.text('正在思考'), findsNothing);
    expect(find.text('正在推进目标：完成当前目标'), findsOneWidget);
    final dots = List<Finder>.generate(
      3,
      (index) => find.byKey(ValueKey('live-thinking-dot-$index')),
    );
    for (final dot in dots) {
      expect(dot, findsOneWidget);
    }

    List<double> verticalOffsets() => dots
        .map((dot) => tester.widget<Transform>(dot).transform.storage[13])
        .toList(growable: false);

    final firstOffsets = verticalOffsets();
    expect(firstOffsets.toSet(), hasLength(greaterThan(1)));
    await tester.pump(const Duration(milliseconds: 180));
    final nextOffsets = verticalOffsets();
    expect(nextOffsets, isNot(firstOffsets));
    expect(nextOffsets.toSet(), hasLength(greaterThan(1)));

    final loaderCenter = tester.getCenter(
      find.byKey(const Key('live-thinking-loader')),
    );
    final timelineFinder = find.descendant(
      of: find.byKey(
        const ValueKey('conversation-timeline-no-workspace:thread-1'),
      ),
      matching: find.byType(ListView),
    );
    final timeline = tester.widget<ListView>(timelineFinder);
    expect(timeline.controller!.position.maxScrollExtent, greaterThan(100));
    timeline.controller!.jumpTo(
      timeline.controller!.position.maxScrollExtent - 100,
    );
    await tester.pump();
    expect(
      tester.getCenter(find.byKey(const Key('live-thinking-loader'))),
      loaderCenter,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders the server-declared live activity before thinking', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'search-1',
            'type': 'webSearch',
            'query': 'Codex App Server',
          },
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('live-activity-row')), findsOneWidget);
    expect(find.byKey(const Key('live-activity-shimmer')), findsOneWidget);
    expect(find.text('正在搜索网页 Codex App Server'), findsOneWidget);
    expect(find.byKey(const Key('live-thinking-row')), findsNothing);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {'id': 'search-1', 'type': 'webSearch'},
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('live-activity-row')), findsNothing);
    expect(find.byKey(const Key('live-thinking-row')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps skill and subagent status rows visible across live completion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(620, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: CodexAppServer())
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'skill-1',
              'type': 'dynamicToolCall',
              'namespace': 'skills',
              'tool': 'read',
              'status': 'completed',
              'success': true,
              'arguments': {'name': 'code-review'},
            },
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/started',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'spawn-1',
              'type': 'collabToolCall',
              'tool': 'spawnAgent',
              'newThreadId': 'review-thread',
              'agentStatus': {
                'name': 'Independent review',
                'status': 'running',
              },
            },
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(find.text('已读取 Code Review 技能'), findsOneWidget);
      expect(find.text('Independent review'), findsOneWidget);
      expect(find.text('已开始工作'), findsOneWidget);
      expect(find.byKey(const Key('live-activity-row')), findsOneWidget);
      expect(tester.takeException(), isNull);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'spawn-1',
              'type': 'collabToolCall',
              'tool': 'spawnAgent',
              'status': 'completed',
              'newThreadId': 'review-thread',
              'agentStatus': {
                'name': 'Independent review',
                'status': 'running',
              },
            },
          },
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('live-activity-row')), findsNothing);
      expect(
        find.byKey(const Key('conversation-activity-review-thread')),
        findsOneWidget,
      );
      expect(find.text('已开始工作'), findsOneWidget);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'wait-1',
              'type': 'collabToolCall',
              'tool': 'waitAgent',
              'status': 'completed',
              'receiverThreadId': 'review-thread',
              'agentStatus': {'status': 'completed'},
            },
          },
        ),
      );
      await tester.pump();

      expect(find.text('Independent review'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('shows every running subagent in the active session timeline', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    void send(String method, Map<String, dynamic> item) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: method,
          params: {'threadId': 'thread-1', 'turnId': 'turn-1', 'item': item},
        ),
      );
    }

    send('item/started', {
      'id': 'spawn-review',
      'type': 'collabToolCall',
      'newThreadId': 'review-thread',
      'agentStatus': {'name': 'Review changes', 'status': 'running'},
    });
    send('item/started', {
      'id': 'spawn-tests',
      'type': 'collabToolCall',
      'newThreadId': 'test-thread',
      'agentStatus': {'name': 'Check tests', 'status': 'running'},
    });

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(
      find.byKey(const Key('live-collaboration-activities-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('live-subagent-activity-open-spawn-review')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('live-subagent-activity-open-spawn-tests')),
      findsOneWidget,
    );
    expect(find.text('Review changes'), findsOneWidget);
    expect(find.text('Check tests'), findsOneWidget);
    expect(find.text('已开始工作'), findsOneWidget);

    send('item/completed', {
      'id': 'spawn-review',
      'type': 'collabToolCall',
      'tool': 'spawnAgent',
      'newThreadId': 'review-thread',
      'agentStatus': {'name': 'Review changes', 'status': 'running'},
    });
    await tester.pump();

    expect(
      find.byKey(const ValueKey('live-subagent-activity-open-spawn-review')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('live-subagent-activity-open-spawn-tests')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('conversation-activity-review-thread')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'opens a real subagent thread in the inspector across window breakpoints',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1320, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const clipboardChannel = MethodChannel('codex_desk/clipboard');
      const draftAttachmentPath = '/tmp/CodexDeskClipboard/subagent-draft.txt';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var deleteCalls = 0;
      messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
        switch (call.method) {
          case 'readFileItems':
            return [
              {
                'path': draftAttachmentPath,
                'isDirectory': false,
                'isTemporary': true,
              },
            ];
          case 'deleteTemporaryItem':
            expect(call.arguments, draftAttachmentPath);
            deleteCalls++;
            return true;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(clipboardChannel, null),
      );
      final server = FakeCodexAppServer()
        ..turnPage = {
          'data': [
            {
              'id': 'child-turn-1',
              'status': {'type': 'completed'},
              'startedAt': 1,
              'completedAt': 4,
              'itemsView': 'full',
              'items': [
                {
                  'id': 'child-answer-1',
                  'type': 'agentMessage',
                  'text': '已检查移动端样式，并整理了可执行结论。',
                },
              ],
            },
          ],
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'id': 'spawn-1',
              'type': 'collabToolCall',
              'tool': 'spawnAgent',
              'status': 'completed',
              'newThreadId': 'review-thread',
              'prompt': '定位移动端样式',
              'agentStatus': {
                'name': 'Locate mobile styles',
                'status': 'running',
              },
            },
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.enterText(
        find.byKey(const Key('composer-field')),
        '尚未发送的主任务草稿',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('subagent-activity-open')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('subagent-thread-panel')), findsOneWidget);
      expect(find.text('Locate mobile styles'), findsWidgets);
      expect(find.text('定位移动端样式'), findsOneWidget);
      expect(find.text('已处理 3 秒'), findsOneWidget);
      expect(find.text('已检查移动端样式，并整理了可执行结论。'), findsOneWidget);
      expect(server.resumeCalls, 0);

      await tester.binding.setSurfaceSize(const Size(820, 720));
      await tester.pump();
      expect(find.byKey(const Key('subagent-thread-panel')), findsOneWidget);
      expect(find.byKey(const Key('inspector-resize-handle')), findsNothing);

      await tester.tap(find.byKey(const Key('side-panel-collapse')));
      await tester.pump();
      expect(find.byKey(const Key('subagent-thread-panel')), findsNothing);
      expect(find.text('Locate mobile styles'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('composer-field')))
            .controller
            ?.text,
        '尚未发送的主任务草稿',
      );
      expect(
        find.byKey(Key('composer-attachment-$draftAttachmentPath')),
        findsOneWidget,
      );
      expect(deleteCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(deleteCalls, 1);
    },
  );

  testWidgets(
    'shows a retryable subagent error while the runtime is disconnected',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(820, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.stopped;
      controller.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.activity,
          title: 'Offline review',
          detail: '已完成',
          createdAt: DateTime(2026),
          sourceItemId: 'offline-review-thread',
          activityKind: 'collaboration',
          activityStatus: 'completed',
          linkedThreadId: 'offline-review-thread',
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.tap(find.byKey(const Key('subagent-activity-open')));
      await tester.pump();

      expect(find.byKey(const Key('subagent-thread-panel')), findsOneWidget);
      expect(find.textContaining('Codex 运行时未连接'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('子智能体尚未产生可显示内容'), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.textContaining('Codex 运行时未连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('opens a nested subagent from the read-only inspector', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final server = FakeCodexAppServer()
      ..turnPage = {
        'data': [
          {
            'id': 'child-turn-1',
            'status': {'type': 'inProgress'},
            'itemsView': 'full',
            'items': [
              {
                'id': 'nested-spawn-1',
                'type': 'collabToolCall',
                'tool': 'spawnAgent',
                'newThreadId': 'nested-review-thread',
                'prompt': '检查嵌套结果',
                'agentStatus': {'name': 'Nested review', 'status': 'running'},
              },
            ],
          },
        ],
      };
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.activity,
        title: 'Parent review',
        detail: '已开始工作',
        createdAt: DateTime(2026),
        sourceItemId: 'parent-review-thread',
        activityKind: 'collaboration',
        activityStatus: 'working',
        linkedThreadId: 'parent-review-thread',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('subagent-activity-open')));
    await tester.pump();
    await tester.pump();

    final panel = find.byKey(const Key('subagent-thread-panel'));
    final nestedOpen = find.descendant(
      of: panel,
      matching: find.byKey(const Key('subagent-activity-open')),
    );
    expect(nestedOpen, findsOneWidget);

    server.turnPage = {
      'data': [
        {
          'id': 'nested-turn-1',
          'status': {'type': 'completed'},
          'itemsView': 'full',
          'items': [
            {
              'id': 'nested-answer-1',
              'type': 'agentMessage',
              'text': '嵌套子智能体已返回结果。',
            },
          ],
        },
      ],
    };
    await tester.tap(nestedOpen);
    await tester.pump();
    await tester.pump();

    expect(
      controller.subagentThreadView('nested-review-thread')?.title,
      'Nested review',
    );
    expect(find.text('嵌套子智能体已返回结果。'), findsOneWidget);
    expect(server.resumeCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'bounds subagent history views and invalidates old workspace reads',
    () async {
      final nextWorkspace = await Directory.systemTemp.createTemp(
        'codex-desk-subagent-workspace-',
      );
      addTearDown(() => nextWorkspace.delete(recursive: true));
      final server = FakeCodexAppServer();
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
        conversationHistoryStore: MemoryConversationHistoryStore(),
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '/workspace-one'
        ..status = RuntimeStatus.stopped;

      for (var index = 0; index < 9; index++) {
        await controller.loadSubagentThread(
          threadId: 'child-$index',
          title: 'Child $index',
        );
      }

      expect(controller.subagentThreadView('child-0'), isNull);
      expect(controller.subagentThreadView('child-1'), isNotNull);
      expect(controller.subagentThreadView('child-8'), isNotNull);

      final delayedPage = Completer<JsonMap>();
      server.turnPageCompleter = delayedPage;
      final delayedLoad = controller.loadSubagentThread(
        threadId: 'old-workspace-child',
        title: 'Old workspace child',
      );
      await Future<void>.delayed(Duration.zero);

      await controller.selectWorkspace(nextWorkspace.path);
      delayedPage.complete({
        'data': [
          {
            'id': 'late-turn',
            'itemsView': 'full',
            'items': [
              {'id': 'late-answer', 'type': 'agentMessage', 'text': '不应写入新工作区'},
            ],
          },
        ],
      });
      await delayedLoad;

      expect(controller.subagentThreadView('old-workspace-child'), isNull);
      expect(controller.subagentThreadView('child-8'), isNull);
      controller.dispose();
    },
  );

  test(
    'ends subagent loading and marks working views stale after runtime exit',
    () async {
      final server = FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await controller.loadSubagentThread(
        threadId: 'loaded-child',
        title: 'Loaded child',
      );
      expect(controller.subagentThreadView('loaded-child')?.status, 'working');

      final delayedPage = Completer<JsonMap>();
      server.turnPageCompleter = delayedPage;
      final delayedLoad = controller.loadSubagentThread(
        threadId: 'loading-child',
        title: 'Loading child',
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.subagentThreadView('loading-child')?.loading, isTrue);

      controller.handleServerEventForTesting(
        const ServerEvent(method: 'runtime/exited', params: {'code': 1}),
      );

      final loadedView = controller.subagentThreadView('loaded-child')!;
      final loadingView = controller.subagentThreadView('loading-child')!;
      expect(loadedView.status, 'stopped');
      expect(loadedView.error, contains('运行时连接已变化'));
      expect(loadingView.loading, isFalse);
      expect(loadingView.status, 'stopped');
      expect(loadingView.error, contains('运行时连接已变化'));

      delayedPage.complete({
        'data': [
          {
            'id': 'late-turn',
            'status': {'type': 'completed'},
            'itemsView': 'full',
            'items': [
              {'id': 'late-answer', 'type': 'agentMessage', 'text': '迟到结果'},
            ],
          },
        ],
      });
      await delayedLoad;

      final retainedView = controller.subagentThreadView('loading-child')!;
      expect(retainedView.loading, isFalse);
      expect(retainedView.status, 'stopped');
      expect(retainedView.error, contains('运行时连接已变化'));
      expect(retainedView.entries, isEmpty);
      controller.dispose();
    },
  );
}
