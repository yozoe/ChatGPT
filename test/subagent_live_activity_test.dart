import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retains every concurrent child agent until its own completion', () {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'parent-thread'
      ..activeTurnId = 'parent-turn';

    void send(String method, Map<String, dynamic> item) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: method,
          params: {
            'threadId': 'parent-thread',
            'turnId': 'parent-turn',
            'item': item,
          },
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

    expect(
      controller.activeCollaborationActivities.map(
        (activity) => activity.linkedThreadId,
      ),
      ['review-thread', 'test-thread'],
    );

    send('item/completed', {
      'id': 'spawn-review',
      'type': 'collabToolCall',
      'newThreadId': 'review-thread',
      'agentStatus': {'name': 'Review changes', 'status': 'running'},
    });

    expect(
      controller.activeCollaborationActivities.map(
        (activity) => activity.linkedThreadId,
      ),
      ['test-thread'],
    );
    controller.dispose();
  });

  test(
    'shows outer collaboration activities from the workspace bridge',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'codex-desk-collaboration-bridge-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final bridgeDirectory = await Directory(
        '${workspace.path}${Platform.pathSeparator}.codex',
      ).create();
      final bridge = File(
        '${bridgeDirectory.path}${Platform.pathSeparator}codex-desk-collaboration.json',
      );
      await bridge.writeAsString(
        jsonEncode({
          'activities': [
            {
              'id': 'external-review',
              'title': '全局代码审查',
              'status': 'started',
              'parentThreadId': 'parent-thread',
              'prompt': '审查未提交改动',
            },
            {
              'id': 'external-finished',
              'title': '已完成任务',
              'status': 'completed',
              'parentThreadId': 'parent-thread',
            },
            {
              'id': 'external-active',
              'title': '活动状态兼容',
              'parentThreadId': 'parent-thread',
              'agentStatus': {'state': 'in_progress'},
            },
            {'id': 'external-unscoped', 'title': '其他会话任务', 'status': 'started'},
          ],
        }),
      );
      final runtime = FakeRuntimeConfigurationStore()
        ..workspace = workspace.path;
      final controller = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtime,
      );
      await controller.waitForInitialConfiguration();
      controller.activeThreadId = 'parent-thread';
      await controller.refreshCollaborationBridgeForTesting();

      expect(controller.activeCollaborationActivities, hasLength(2));
      expect(
        controller.activeCollaborationActivities.map((a) => a.label),
        containsAll(<String>['全局代码审查', '活动状态兼容']),
      );
      expect(
        controller.activeCollaborationActivities.every(
          (activity) => activity.isExternalBridge,
        ),
        isTrue,
      );
      expect(
        controller.entries.any(
          (entry) =>
              entry.sourceItemId == 'external-bridge-external-finished' &&
              entry.activityStatus == 'completed' &&
              entry.activityParentThreadId == 'parent-thread',
        ),
        isTrue,
      );
      controller.dispose();
    },
  );

  test('does not leak bridge activities from another parent session', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'codex-desk-collaboration-scope-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final bridgeDirectory = await Directory(
      '${workspace.path}${Platform.pathSeparator}.codex',
    ).create();
    await File(
      '${bridgeDirectory.path}${Platform.pathSeparator}codex-desk-collaboration.json',
    ).writeAsString(
      jsonEncode({
        'activities': [
          {
            'id': 'other-session',
            'title': '另一个会话',
            'status': 'started',
            'parentThreadId': 'other-parent',
          },
          {
            'id': 'current-session',
            'title': '当前会话',
            'status': 'started',
            'parentThreadId': 'current-parent',
          },
        ],
      }),
    );
    final runtime = FakeRuntimeConfigurationStore()..workspace = workspace.path;
    final controller = CodexController(
      server: CodexAppServer(),
      runtimeConfigurationStore: runtime,
    );
    await controller.waitForInitialConfiguration();
    controller.activeThreadId = 'current-parent';
    await controller.refreshCollaborationBridgeForTesting();

    expect(
      controller.activeCollaborationActivities.map(
        (activity) => activity.label,
      ),
      ['当前会话'],
    );
    expect(
      controller.entries.where(
        (entry) => entry.activityKind == 'collaboration',
      ),
      hasLength(1),
    );
    controller.dispose();
  });

  test(
    'removes unscoped legacy bridge rows even with a real child thread',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'codex-desk-legacy-bridge-rows-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final runtime = FakeRuntimeConfigurationStore()
        ..workspace = workspace.path;
      final history = MemoryConversationHistoryStore();
      final firstController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtime,
        conversationHistoryStore: history,
      );
      await firstController.waitForInitialConfiguration();
      firstController.activeThreadId = 'current-parent';
      firstController.replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.activity,
          title: '旧会话中的子智能体',
          detail: '正在工作',
          createdAt: DateTime.now(),
          sourceItemId: 'external-bridge-old-activity',
          activityKind: 'collaboration',
          linkedThreadId: 'real-child-thread',
        ),
      ]);
      await firstController.saveConversationHistoryForTesting();
      firstController.dispose();

      final restoredController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtime,
        conversationHistoryStore: history,
      );
      await restoredController.waitForInitialConfiguration();

      expect(
        restoredController.entries.where(
          (entry) => entry.sourceItemId == 'external-bridge-old-activity',
        ),
        isEmpty,
      );
      restoredController.dispose();
    },
  );

  test(
    'retains a scoped bridge completion without a child thread after restart',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'codex-desk-scoped-bridge-history-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final bridgeDirectory = await Directory(
        '${workspace.path}${Platform.pathSeparator}.codex',
      ).create();
      final bridge = File(
        '${bridgeDirectory.path}${Platform.pathSeparator}codex-desk-collaboration.json',
      );
      await bridge.writeAsString(
        jsonEncode({
          'activities': [
            {
              'id': 'completed-without-child',
              'title': '外层审查',
              'status': 'completed',
              'parentThreadId': 'parent-thread',
            },
          ],
        }),
      );
      final runtime = FakeRuntimeConfigurationStore()
        ..workspace = workspace.path;
      final history = MemoryConversationHistoryStore();
      final firstController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtime,
        conversationHistoryStore: history,
      );
      await firstController.waitForInitialConfiguration();
      firstController.activeThreadId = 'parent-thread';
      await firstController.refreshCollaborationBridgeForTesting();
      await firstController.saveConversationHistoryForTesting();
      firstController.dispose();
      await bridge.writeAsString(jsonEncode({'activities': []}));

      final restoredController = CodexController(
        server: CodexAppServer(),
        runtimeConfigurationStore: runtime,
        conversationHistoryStore: history,
      );
      await restoredController.waitForInitialConfiguration();

      expect(
        restoredController.entries.any(
          (entry) =>
              entry.sourceItemId == 'external-bridge-completed-without-child' &&
              entry.activityParentThreadId == 'parent-thread',
        ),
        isTrue,
      );
      restoredController.dispose();
    },
  );
}
