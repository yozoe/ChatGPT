import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

CodexThread historyThread(String id) =>
    CodexThread(id: id, preview: 'preview-$id', createdAt: 1, updatedAt: 2);

Future<CodexController> historyController(FakeCodexAppServer server) async {
  final controller = CodexController(
    server: server,
    runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
  );
  await controller.waitForInitialConfiguration();
  controller
    ..workspacePath = '/workspace'
    ..status = RuntimeStatus.ready;
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads user, agent, and command history when resuming', () async {
    final server = FakeCodexAppServer()
      ..resumeResult = {
        'thread': {
          'turns': [
            {
              'id': 'turn-1',
              'items': [
                {
                  'id': 'user-item',
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': '历史问题'},
                  ],
                },
                {'id': 'agent-item', 'type': 'agentMessage', 'text': '历史回答'},
                {
                  'id': 'command-item',
                  'type': 'commandExecution',
                  'command': 'dart test',
                  'aggregatedOutput': 'All tests passed',
                },
                {
                  'id': 'search-item',
                  'type': 'webSearch',
                  'query': 'Codex App Server',
                  'results': [{}, {}],
                },
                {
                  'id': 'mcp-item',
                  'type': 'mcpToolCall',
                  'server': 'docs',
                  'tool': 'search',
                  'status': 'completed',
                },
              ],
            },
          ],
        },
      };
    final controller = await historyController(server);

    await controller.resumeThread(historyThread('history-thread'));

    expect(
      controller.entries.map((entry) => '${entry.title}:${entry.detail}'),
      containsAll([
        '你:历史问题',
        'Codex:历史回答',
        '执行命令:dart test\nAll tests passed',
        '网页搜索:Codex App Server · 2 条结果',
        'MCP 工具：docs/search:completed',
      ]),
    );
    controller.dispose();
  });

  test('restores file changes from only the latest historical turn', () async {
    final server = FakeCodexAppServer()
      ..resumeResult = {
        'thread': {
          'turns': [
            {
              'id': 'turn-1',
              'startedAt': 1,
              'items': [
                {
                  'type': 'fileChange',
                  'changes': [
                    {'path': 'first.txt', 'kind': 'modified', 'diff': '+first'},
                  ],
                },
              ],
            },
            {
              'id': 'turn-2',
              'startedAt': 2,
              'items': [
                {'type': 'agentMessage', 'text': 'No files changed.'},
              ],
            },
          ],
        },
      };
    final controller = await historyController(server);

    await controller.resumeThread(historyThread('history-thread'));

    expect(controller.fileChanges, isEmpty);
    expect(controller.turnDiff, isNull);
    controller.dispose();
  });

  test('marks history restoration separately from live output', () async {
    final controller = await historyController(FakeCodexAppServer());
    final restorationStates = <bool>[];
    controller.addListener(
      () => restorationStates.add(controller.isResumingThread),
    );

    await controller.resumeThread(historyThread('history-thread'));

    expect(restorationStates, contains(true));
    expect(restorationStates.last, isFalse);
    expect(controller.isResumingThread, isFalse);
    controller.dispose();
  });

  test('restores a previously opened task view from memory', () async {
    final controller = await historyController(FakeCodexAppServer());
    final first = historyThread('first-thread');
    final second = historyThread('second-thread');

    await controller.resumeThread(first);
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: 'first cached page',
        createdAt: DateTime(2026),
      ),
    ]);
    await controller.resumeThread(second);
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: 'second page',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    ]);

    await controller.resumeThread(first);

    expect(controller.entries.single.detail, 'first cached page');
    expect(controller.hasCachedActiveThreadView, isTrue);
    controller.dispose();
  });

  test('retains only the most recently opened task views in memory', () async {
    final controller = await historyController(FakeCodexAppServer());

    for (var index = 0; index < 9; index++) {
      await controller.resumeThread(historyThread('thread-$index'));
    }

    expect(controller.cachedThreadViewIds, hasLength(8));
    expect(controller.cachedThreadViewIds, isNot(contains('thread-0')));
    expect(controller.cachedThreadViewIds, contains('thread-8'));
    controller.dispose();
  });

  test('hydrates older turns when resume returns a cursor', () async {
    final server = FakeCodexAppServer()
      ..resumeResult = {
        'turnsBackwardsCursor': 'older-cursor',
        'thread': {
          'turns': [
            {
              'id': 'new-turn',
              'startedAt': 2,
              'items': [
                {'id': 'new-agent', 'type': 'agentMessage', 'text': '新回答'},
              ],
            },
          ],
        },
      }
      ..turnPage = {
        'data': [
          {
            'id': 'old-turn',
            'startedAt': 1,
            'items': [
              {
                'id': 'old-user',
                'type': 'userMessage',
                'content': [
                  {'type': 'text', 'text': '旧问题'},
                ],
              },
            ],
          },
        ],
        'nextCursor': null,
      };
    final controller = await historyController(server);

    await controller.resumeThread(historyThread('paginated-thread'));

    expect(server.turnPageCursors, ['older-cursor']);
    final details = controller.entries.map((entry) => entry.detail).toList();
    expect(details.indexOf('旧问题'), lessThan(details.indexOf('新回答')));
    controller.dispose();
  });

  test('hydrates unloaded turn items through item pagination', () async {
    final server = FakeCodexAppServer()
      ..resumeResult = {
        'thread': {
          'turns': [
            {
              'id': 'summary-turn',
              'itemsView': 'notLoaded',
              'items': <Object?>[],
            },
          ],
        },
      }
      ..itemPage = {
        'data': [
          {
            'turnId': 'summary-turn',
            'item': {
              'id': 'hydrated-agent',
              'type': 'agentMessage',
              'text': '按项分页恢复的回答',
            },
          },
        ],
        'nextCursor': null,
      };
    final controller = await historyController(server);

    await controller.resumeThread(historyThread('item-history-thread'));

    expect(server.itemPageTurnIds, ['summary-turn']);
    expect(
      controller.entries.map((entry) => entry.detail),
      contains('按项分页恢复的回答'),
    );
    controller.dispose();
  });

  test('restores collaboration and context compaction history', () async {
    final server = FakeCodexAppServer()
      ..resumeResult = {
        'thread': {
          'turns': [
            {
              'id': 'turn-1',
              'items': [
                {
                  'id': 'collab-1',
                  'type': 'collabToolCall',
                  'tool': 'spawnAgent',
                  'status': 'completed',
                  'newThreadId': 'review-thread',
                  'agentStatus': {
                    'name': 'Independent review',
                    'status': 'completed',
                  },
                },
                {'id': 'compact-1', 'type': 'contextCompaction'},
              ],
            },
          ],
        },
      };
    final controller = await historyController(server);

    await controller.resumeThread(historyThread('activity-history-thread'));

    expect(
      controller.entries.map((entry) => entry.title),
      containsAll(['Independent review', '压缩对话上下文']),
    );
    final activity = controller.entries.singleWhere(
      (entry) => entry.kind == TimelineKind.activity,
    );
    expect(activity.detail, '已完成');
    expect(activity.sourceItemId, 'review-thread');
    expect(activity.activityStatus, 'completed');
    controller.dispose();
  });

  test('does not show the prior timeline when item hydration fails', () async {
    final server = FakeCodexAppServer()
      ..resumeResult = {
        'thread': {
          'turns': [
            {
              'id': 'unavailable-turn',
              'itemsView': 'notLoaded',
              'items': <Object?>[],
            },
          ],
        },
      }
      ..itemPageError = StateError('items unavailable');
    final controller = await historyController(server);
    controller.activeThreadId = 'old-thread';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'old-message', 'delta': '旧线程回答'},
      ),
    );

    await controller.resumeThread(historyThread('target-thread'));

    expect(controller.activeThreadId, 'target-thread');
    expect(server.resumedThreadId, 'target-thread');
    expect(
      controller.entries.map((entry) => entry.detail),
      isNot(contains('旧线程回答')),
    );
    expect(
      controller.entries.map((entry) => entry.title),
      contains('历史内容加载不完整'),
    );
    controller.dispose();
  });

  test(
    'keeps partial item history when a turn exceeds the page limit',
    () async {
      final pages = List<Map<String, Object?>>.generate(
        20,
        (index) => {
          'data': [
            {
              'turnId': 'long-turn',
              'item': {
                'id': 'item-$index',
                'type': 'agentMessage',
                'text': '第 $index 项',
              },
            },
          ],
          'nextCursor': 'cursor-$index',
        },
      );
      final server = FakeCodexAppServer()
        ..resumeResult = {
          'thread': {
            'turns': [
              {
                'id': 'long-turn',
                'itemsView': 'notLoaded',
                'items': <Object?>[],
              },
            ],
          },
        }
        ..itemPages = pages;
      final controller = await historyController(server);

      await controller.resumeThread(historyThread('long-history-thread'));

      expect(controller.activeThreadId, 'long-history-thread');
      expect(server.itemPageTurnIds, hasLength(20));
      expect(
        controller.entries.map((entry) => entry.title),
        contains('历史内容未完全加载'),
      );
      controller.dispose();
    },
  );
}
