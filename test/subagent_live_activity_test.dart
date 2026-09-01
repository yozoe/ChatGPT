import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
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
              entry.activityStatus == 'completed',
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
}
