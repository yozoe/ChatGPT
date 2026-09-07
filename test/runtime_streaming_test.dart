import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coalesces agent deltas into one timeline entry', () async {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'message-1', 'delta': 'Hello'},
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {'itemId': 'message-1', 'delta': ' world'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final agentEntries = controller.entries
        .where((entry) => entry.kind == TimelineKind.agent)
        .toList();
    expect(agentEntries, hasLength(1));
    expect(agentEntries.single.detail, 'Hello world');
    controller.dispose();
  });

  test('throttles reasoning summary delta notifications', () async {
    final controller = CodexController(server: CodexAppServer());
    await controller.waitForInitialConfiguration();
    controller
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {'id': 'reasoning-1', 'type': 'reasoning', 'summary': []},
        },
      ),
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    for (final delta in ['**Planning ', 'the regression fix**']) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/reasoning/summaryTextDelta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reasoning-1',
            'summaryIndex': 0,
            'delta': delta,
          },
        ),
      );
    }

    expect(notifications, 0);
    expect(controller.activeLiveActivity?.label, 'Planning the regression fix');

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(notifications, 1);
    expect(controller.activeLiveActivity?.label, 'Planning the regression fix');
    controller.dispose();
  });

  test('tracks a live command and persists the completed turn duration', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1';

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/started',
        params: {
          'turn': {'id': 'turn-1', 'startedAt': 1000},
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
            'command': 'dart test',
          },
        },
      ),
    );

    expect(controller.activeCommand, 'dart test');

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'command-1',
            'type': 'commandExecution',
            'command': 'dart test',
            'aggregatedOutput': 'All tests passed',
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'thread-1',
          'turn': {'id': 'turn-1', 'status': 'completed', 'durationMs': 63000},
        },
      ),
    );

    expect(controller.activeCommand, isNull);
    expect(controller.activeTurnId, isNull);
    expect(
      controller.entries.map((entry) => '${entry.title}:${entry.detail}'),
      containsAll(['执行命令:dart test\nAll tests passed', '耗时 1 分钟 3 秒:']),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'late-command',
            'type': 'commandExecution',
            'command': 'should not appear',
          },
        },
      ),
    );
    expect(controller.activeCommand, isNull);
    controller.dispose();
  });

  test('uses App Server item types for the live turn status', () {
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
            'query': 'Codex App Server protocol',
          },
        },
      ),
    );

    expect(controller.activeLiveActivity?.label, '正在搜索网页');
    expect(controller.activeLiveActivity?.detail, 'Codex App Server protocol');
    expect(controller.activeCommand, isNull);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/started',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'mcp-1',
            'type': 'mcpToolCall',
            'server': 'docs',
            'tool': 'search',
          },
        },
      ),
    );
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

    expect(controller.activeLiveActivity?.label, '正在调用 MCP 工具');
    expect(controller.activeLiveActivity?.detail, 'docs/search');

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {'id': 'mcp-1', 'type': 'mcpToolCall'},
        },
      ),
    );

    expect(controller.activeLiveActivity, isNull);
    controller.dispose();
  });

  test('uses parsed command actions for specific filesystem statuses', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    void startItem(Map<String, Object?> item) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/started',
          params: {'threadId': 'thread-1', 'turnId': 'turn-1', 'item': item},
        ),
      );
    }

    startItem({
      'id': 'read-1',
      'type': 'commandExecution',
      'command': "sed -n '1,80p' test/app_shell_test.dart",
      'commandActions': [
        {
          'type': 'read',
          'command': "sed -n '1,80p' test/app_shell_test.dart",
          'name': 'app_shell_test.dart',
          'path': 'test/app_shell_test.dart',
        },
      ],
    });
    expect(controller.activeLiveActivity?.kind, 'fileRead');
    expect(controller.activeLiveActivity?.label, '正在读取');
    expect(controller.activeLiveActivity?.detail, 'app_shell_test.dart');
    expect(controller.activeCommand, isNull);

    startItem({
      'id': 'search-1',
      'type': 'commandExecution',
      'command': 'rg AppDelegate.swift macos',
      'commandActions': [
        {
          'type': 'search',
          'command': 'rg AppDelegate.swift macos',
          'query': 'AppDelegate.swift',
          'path': 'macos',
        },
      ],
    });
    expect(controller.activeLiveActivity?.kind, 'fileSearch');
    expect(controller.activeLiveActivity?.label, '正在搜索');
    expect(
      controller.activeLiveActivity?.detail,
      '“AppDelegate.swift” · macos 文件夹',
    );

    startItem({
      'id': 'list-1',
      'type': 'commandExecution',
      'command': 'find macos/Runner.xcodeproj/xcshareddata/xcschemes',
      'commandActions': [
        {
          'type': 'listFiles',
          'command': 'find macos/Runner.xcodeproj/xcshareddata/xcschemes',
          'path': 'macos/Runner.xcodeproj/xcshareddata/xcschemes',
        },
      ],
    });
    expect(controller.activeLiveActivity?.kind, 'fileList');
    expect(controller.activeLiveActivity?.label, '正在列出');
    expect(controller.activeLiveActivity?.detail, 'xcschemes 文件夹中的文件');

    startItem({
      'id': 'compound-1',
      'type': 'commandExecution',
      'command': "sed -n '1,80p' lib/main.dart && flutter test",
      'commandActions': [
        {'type': 'read', 'name': 'main.dart', 'path': 'lib/main.dart'},
        {'type': 'unknown', 'command': 'flutter test'},
      ],
    });
    expect(controller.activeLiveActivity?.kind, 'commandExecution');
    expect(controller.activeLiveActivity?.label, '正在运行命令');
    expect(
      controller.activeLiveActivity?.detail,
      "sed -n '1,80p' lib/main.dart && flutter test",
    );
    expect(controller.activeCommand, contains('flutter test'));

    startItem({
      'id': 'edit-1',
      'type': 'fileChange',
      'status': 'inProgress',
      'changes': [
        {'path': 'lib/main.dart', 'kind': 'update'},
      ],
    });
    expect(controller.activeLiveActivity?.kind, 'fileChange');
    expect(controller.activeLiveActivity?.label, '正在编辑文件');
    expect(controller.activeLiveActivity?.detail, isEmpty);
    controller.dispose();
  });

  test('streams the current reasoning summary as the live status', () {
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
          'item': {'id': 'reasoning-1', 'type': 'reasoning', 'summary': []},
        },
      ),
    );
    expect(controller.activeLiveActivity?.label, '正在分析');

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/reasoning/summaryPartAdded',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'reasoning-1',
          'summaryIndex': 0,
        },
      ),
    );
    for (final delta in ['**Planning ', 'Xcode unit test implementation**']) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/reasoning/summaryTextDelta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reasoning-1',
            'summaryIndex': 0,
            'delta': delta,
          },
        ),
      );
    }
    expect(controller.activeLiveActivity?.kind, 'reasoning');
    expect(
      controller.activeLiveActivity?.label,
      'Planning Xcode unit test implementation',
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
            'command': 'flutter test',
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/reasoning/summaryTextDelta',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'reasoning-1',
          'summaryIndex': 0,
          'delta': ' ignored',
        },
      ),
    );
    expect(controller.activeLiveActivity?.kind, 'commandExecution');
    expect(controller.activeCommand, 'flutter test');
    controller.dispose();
  });

  test('labels a dynamic skill reader with the skill name', () {
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
            'id': 'skill-reader-1',
            'type': 'dynamicToolCall',
            'namespace': 'skills',
            'tool': 'read',
            'arguments': {'name': 'code-review'},
          },
        },
      ),
    );

    expect(controller.activeLiveActivity?.kind, 'skillRead');
    expect(controller.activeLiveActivity?.label, '正在读取 Code Review 技能');
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': {
            'id': 'skill-reader-1',
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

    expect(controller.activeLiveActivity, isNull);
    final activity = controller.entries.singleWhere(
      (entry) => entry.kind == TimelineKind.activity,
    );
    expect(activity.title, '已读取 Code Review 技能');
    expect(activity.activityKind, 'skillRead');
    expect(activity.activityStatus, 'completed');
    controller.dispose();
  });
}
