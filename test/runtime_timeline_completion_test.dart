import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ignores lifecycle events from a previously resumed thread', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'current-thread';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'threadId': 'current-thread',
          'turn': {'id': 'current-turn'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'current-thread',
          'turnId': 'current-turn',
          'item': {
            'id': 'current-command',
            'type': 'commandExecution',
            'command': 'dart test',
          },
        },
      ),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'threadId': 'previous-thread',
          'turn': {'id': 'previous-turn'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'previous-thread',
          'turnId': 'previous-turn',
          'item': {
            'id': 'previous-file',
            'type': 'fileChange',
            'changes': [
              {'path': 'lib/other.dart', 'kind': 'modified'},
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {
          'threadId': 'previous-thread',
          'turnId': 'previous-turn',
          'diff': 'unrelated diff',
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'previous-thread',
          'turn': {
            'id': 'previous-turn',
            'status': 'completed',
            'durationMs': 63000,
          },
        },
      ),
    );

    expect(controller.status, RuntimeStatus.running);
    expect(controller.activeTurnId, 'current-turn');
    expect(controller.activeCommand, 'dart test');
    expect(controller.fileChanges, isEmpty);
    expect(controller.turnDiff, isNull);
    expect(
      controller.entries.map((entry) => entry.kind),
      isNot(contains(TimelineKind.elapsed)),
    );
    controller.dispose();
  });

  test('ignores delayed lifecycle and plan events with no active task', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'threadId': 'previous-thread',
          'turn': {'id': 'previous-turn'},
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/plan/updated',
        params: {
          'threadId': 'previous-thread',
          'turnId': 'previous-turn',
          'plan': [
            {'step': '旧任务计划', 'status': 'inProgress'},
          ],
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'previous-thread',
          'turnId': 'previous-turn',
          'item': {
            'id': 'previous-command',
            'type': 'commandExecution',
            'command': 'should not appear',
          },
        },
      ),
    );

    expect(controller.activeTurnId, isNull);
    expect(controller.activeTaskPlan, isNull);
    expect(controller.activeCommand, isNull);
    controller.dispose();
  });

  test('orders final answers by App Server phase after command activity', () {
    final entries = [
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '提前到达的最终回复',
        createdAt: DateTime(2026),
        agentPhase: 'final_answer',
      ),
      TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 1 秒',
        detail: '',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '任务已创建',
        detail: 'Thread thread-1',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '我会查阅官方说明',
        createdAt: DateTime(2026),
        agentPhase: 'commentary',
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'search hooks',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '任务完成',
        detail: '',
        createdAt: DateTime(2026),
      ),
    ];

    expect(orderAgentMessagePhases(entries).map((entry) => entry.detail), [
      'Thread thread-1',
      '我会查阅官方说明',
      'search hooks',
      '提前到达的最终回复',
      '',
      '',
    ]);
  });

  test('collapses replayed durations and completions in one user turn', () {
    final entries = [
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: '修复问题',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '已经修复。',
        agentPhase: 'final_answer',
        createdAt: DateTime(2026),
      ),
      for (final seconds in [61, 338, 239])
        TimelineEntry(
          kind: TimelineKind.elapsed,
          title: '耗时 $seconds 秒',
          detail: '',
          createdAt: DateTime(2026),
        ),
      for (var index = 0; index < 3; index++)
        TimelineEntry(
          kind: TimelineKind.system,
          title: '任务完成',
          detail: '你可以继续在同一线程追问。',
          createdAt: DateTime(2026),
        ),
    ];

    final ordered = orderAgentMessagePhases(entries);

    expect(
      ordered.where((entry) => entry.kind == TimelineKind.elapsed),
      hasLength(1),
    );
    expect(ordered.where((entry) => entry.title == '任务完成'), hasLength(1));
    expect(ordered.map((entry) => entry.title), [
      '你',
      'Codex',
      '耗时 61 秒',
      '任务完成',
    ]);
  });

  test(
    'compacts three consecutive duration-only turns without losing detail',
    () {
      final entries = [
        for (var seconds = 1; seconds <= 3; seconds++)
          TimelineEntry(
            kind: TimelineKind.elapsed,
            title: '耗时 $seconds 秒',
            detail: '',
            createdAt: DateTime(2026, 1, 1, 0, 0, seconds),
          ),
      ];

      final items = conversationTimelineItems(entries);

      expect(items, hasLength(1));
      expect(items.single.elapsedEntries, hasLength(3));
      expect(items.single.elapsedEntries!.map((entry) => entry.title), [
        '耗时 1 秒',
        '耗时 2 秒',
        '耗时 3 秒',
      ]);
    },
  );

  test('keeps short duration runs and detailed turns separate', () {
    final entries = [
      TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 1 秒',
        detail: '',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 2 秒',
        detail: '',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '已完成工作',
        createdAt: DateTime(2026),
      ),
    ];

    final items = conversationTimelineItems(entries);

    expect(items, hasLength(3));
    expect(items.where((item) => item.elapsedEntries != null), isEmpty);
  });

  test('retains one duration and completion for each user turn', () {
    final entries = [
      for (var turn = 1; turn <= 2; turn++) ...[
        TimelineEntry(
          kind: TimelineKind.user,
          title: '你',
          detail: '任务 $turn',
          createdAt: DateTime(2026),
        ),
        TimelineEntry(
          kind: TimelineKind.elapsed,
          title: '耗时 $turn 秒',
          detail: '',
          createdAt: DateTime(2026),
        ),
        TimelineEntry(
          kind: TimelineKind.system,
          title: '任务完成',
          detail: '你可以继续在同一线程追问。',
          createdAt: DateTime(2026),
        ),
      ],
    ];

    final normalized = collapseReplayedTurnCompletions(entries);

    expect(
      normalized.where((entry) => entry.kind == TimelineKind.elapsed),
      hasLength(2),
    );
    expect(normalized.where((entry) => entry.title == '任务完成'), hasLength(2));
  });

  test('records agent message phase without splitting streamed deltas', () {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
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
            'id': 'agent-1',
            'type': 'agentMessage',
            'phase': 'final_answer',
          },
        },
      ),
    );
    for (final delta in ['甲', '乙']) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'agent-1',
            'delta': delta,
          },
        ),
      );
    }
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'agent-1',
            'type': 'agentMessage',
            'phase': 'final_answer',
            'text': '甲乙',
          },
        },
      ),
    );

    final agents = controller.entries.where(
      (entry) => entry.kind == TimelineKind.agent,
    );
    expect(agents, hasLength(1));
    expect(agents.single.detail, '甲乙');
    expect(agents.single.agentPhase, 'final_answer');
    controller.dispose();
  });

  test('keeps unphased compatible-server messages in arrival order', () {
    final entries = [
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '兼容消息',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'command',
        createdAt: DateTime(2026),
      ),
    ];

    expect(orderAgentMessagePhases(entries), entries);
  });

  test('repairs a legacy unphased turn with process output after elapsed', () {
    final entries = [
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '最终回复',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 1 秒',
        detail: '',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '任务已创建',
        detail: 'Thread legacy',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'flutter run -d macos',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '任务完成',
        detail: '',
        createdAt: DateTime(2026),
      ),
    ];

    expect(orderAgentMessagePhases(entries).map((entry) => entry.detail), [
      'Thread legacy',
      'flutter run -d macos',
      '最终回复',
      '',
      '',
    ]);
  });

  test('keeps failed and unknown terminal statuses after final answers', () {
    final entries = [
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '失败前回复',
        agentPhase: 'final_answer',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 1 秒',
        detail: '',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: '失败命令',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.error,
        title: '任务失败',
        detail: '失败原因',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: '继续',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '未知状态前回复',
        agentPhase: 'final_answer',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.elapsed,
        title: '耗时 2 秒',
        detail: '',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '任务已结束',
        detail: '未知状态',
        createdAt: DateTime(2026),
      ),
    ];

    expect(orderAgentMessagePhases(entries).map((entry) => entry.detail), [
      '失败命令',
      '失败前回复',
      '',
      '失败原因',
      '继续',
      '未知状态前回复',
      '',
      '未知状态',
    ]);
  });
}
