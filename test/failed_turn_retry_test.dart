import 'dart:async';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

Future<CodexController> readyRetryController(FakeCodexAppServer server) async {
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

  test(
    'offers manual retry only after automatic network waiting finally fails',
    () async {
      final server = FakeCodexAppServer();
      final controller = await readyRetryController(server);
      expect(await controller.sendPrompt('等待网络恢复'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'new-thread',
            'turn': {'id': 'turn-1'},
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'error',
          params: {
            'threadId': 'new-thread',
            'turnId': 'turn-1',
            'willRetry': true,
            'error': {'message': 'offline'},
          },
        ),
      );
      expect(controller.hasFailedTurnRetry, isFalse);
      expect(controller.status, RuntimeStatus.running);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'new-thread',
            'turn': {
              'id': 'turn-1',
              'status': 'failed',
              'error': {'message': 'network retries exhausted'},
            },
          },
        ),
      );
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.hasFailedTurnRetry, isTrue);
      expect(controller.failedTurnRetryError, 'network retries exhausted');
      controller.dispose();
    },
  );

  test('classifies usage-limit failures and keeps explicit recovery', () async {
    final server = FakeCodexAppServer();
    final controller = await readyRetryController(server);
    expect(await controller.sendPrompt('额度测试'), isTrue);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {
            'status': 'failed',
            'error': {
              'code': 'usage_limit_reached',
              'message': "You've hit your usage limit.",
            },
          },
        },
      ),
    );

    expect(controller.hasUsageLimitFailure, isTrue);
    expect(controller.canRetryFailedTurn, isFalse);
    expect(controller.canRetryUsageLimitedTurn, isTrue);
    expect(await controller.retryFailedTurn(), isTrue);
    expect(server.startedTurnPrompts, ['额度测试', '额度测试']);
    expect(controller.hasUsageLimitFailure, isFalse);
    controller.dispose();
  });

  test(
    'keeps a foreground completion routable during a background retry',
    () async {
      final server = FakeCodexAppServer()
        ..startThreadResponseIds.addAll(['thread-a', 'thread-b']);
      final controller = await readyRetryController(server);

      expect(await controller.sendPrompt('任务 A'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'thread-a',
            'turn': {'id': 'turn-a'},
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-a',
            'turn': {
              'id': 'turn-a',
              'status': 'failed',
              'error': {'message': 'offline'},
            },
          },
        ),
      );

      controller.createThread();
      final retryAccepted = Completer<void>();
      server.startTurnCompleter = retryAccepted;
      final backgroundRetry = controller.retryFailedTurn(
        threadIdOverride: 'thread-a',
      );
      for (
        var index = 0;
        index < 10 && !server.startedTurnThreadIds.contains('thread-a');
        index++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(server.startedTurnThreadIds, contains('thread-a'));

      // Let the foreground task submit while the background retry is still
      // waiting for App Server acceptance.
      server.startTurnCompleter = null;
      expect(await controller.sendPrompt('任务 B'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'thread-b',
            'turn': {'id': 'turn-b'},
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-b',
            'turn': {'id': 'turn-b', 'status': 'completed'},
          },
        ),
      );

      expect(controller.status, RuntimeStatus.ready);
      expect(controller.entries.any((entry) => entry.title == '任务完成'), isTrue);

      retryAccepted.complete();
      expect(await backgroundRetry, isTrue);
      controller.dispose();
    },
  );

  test(
    'does not retain foreground handshake markers after switching during goal retry',
    () async {
      final server = FakeCodexAppServer()
        ..startThreadResponseIds.addAll(['thread-a', 'thread-b']);
      final controller = await readyRetryController(server);

      expect(await controller.sendPrompt('任务 A', goal: '目标 A'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-a',
            'turn': {
              'status': 'failed',
              'error': {'message': 'offline'},
            },
          },
        ),
      );

      final goalWrite = Completer<JsonMap?>();
      final retryAccepted = Completer<void>();
      server
        ..setThreadGoalCompleter = goalWrite
        ..startTurnCompleter = retryAccepted;
      final retry = controller.retryFailedTurn();
      for (
        var index = 0;
        index < 10 && server.setThreadGoalCalls < 2;
        index++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(server.setThreadGoalCalls, 2);

      // The retry started in the foreground, but Goal persistence yielded
      // before the protocol request. Switching tasks must make it background.
      controller.createThread();
      goalWrite.complete(null);
      for (
        var index = 0;
        index < 10 && !server.startedTurnThreadIds.contains('thread-a');
        index++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(server.startedTurnThreadIds, contains('thread-a'));

      // Release only the new foreground request; the retry remains pending.
      server.startTurnCompleter = null;
      expect(await controller.sendPrompt('任务 B'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'thread-b',
            'turn': {'id': 'turn-b'},
          },
        ),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-b',
            'turn': {'id': 'turn-b', 'status': 'completed'},
          },
        ),
      );

      expect(controller.status, RuntimeStatus.ready);
      expect(controller.entries.any((entry) => entry.title == '任务完成'), isTrue);

      retryAccepted.complete();
      expect(await retry, isTrue);
      controller.dispose();
    },
  );

  test(
    'classifies structured turn-start errors without English text',
    () async {
      final server = FakeCodexAppServer()
        ..startTurnError = const CodexAppServerException(
          message: '当前请求暂时不可用。',
          code: 'usage_limit_reached',
        );
      final controller = await readyRetryController(server);

      expect(await controller.sendPrompt('结构化额度错误'), isFalse);
      expect(controller.hasUsageLimitFailure, isTrue);
      expect(controller.canRetryFailedTurn, isFalse);
      expect(controller.canRetryUsageLimitedTurn, isTrue);
      controller.dispose();
    },
  );

  test('starts an automatic retry countdown for capacity errors', () async {
    final server = FakeCodexAppServer();
    final controller = await readyRetryController(server);
    expect(await controller.sendPrompt('容量重试'), isTrue);
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {
            'status': 'failed',
            'error': {
              'message':
                  'Selected model is at capacity. Please try a different model.',
            },
          },
        },
      ),
    );
    expect(controller.hasCapacityRateLimitFailure, isTrue);
    expect(controller.hasAutomaticRetry, isTrue);
    expect(controller.automaticRetrySecondsRemaining, inInclusiveRange(29, 30));
    controller.cancelAutomaticRetry();
    expect(controller.hasAutomaticRetry, isFalse);
    expect(controller.automaticRetryCancelled, isTrue);
    expect(controller.canRetryFailedTurn, isTrue);
    controller.dispose();
  });

  test('does not automatically retry long-term usage limits', () async {
    final server = FakeCodexAppServer();
    final controller = await readyRetryController(server);
    expect(await controller.sendPrompt('额度不自动轮询'), isTrue);
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {
            'status': 'failed',
            'error': {'code': 'usage_limit_reached', 'message': 'usage limit'},
          },
        },
      ),
    );
    expect(controller.hasUsageLimitFailure, isTrue);
    expect(controller.hasAutomaticRetry, isFalse);
    controller.dispose();
  });

  test('classifies a numeric structured 429 as a capacity retry', () async {
    final server = FakeCodexAppServer()
      ..startTurnError = const CodexAppServerException(
        message: 'Too many requests',
        code: '429',
      );
    final controller = await readyRetryController(server);
    expect(await controller.sendPrompt('429 重试'), isFalse);
    expect(controller.hasCapacityRateLimitFailure, isTrue);
    expect(controller.hasAutomaticRetry, isTrue);
    controller.cancelAutomaticRetry();
    controller.dispose();
  });

  test(
    'preserves a usage-limit classification when its type mentions capacity',
    () async {
      final server = FakeCodexAppServer()
        ..startTurnError = const CodexAppServerException(
          message: 'Usage limit reached',
          code: 'usage_limit_reached',
          type: 'capacity',
        );
      final controller = await readyRetryController(server);
      expect(await controller.sendPrompt('额度优先级'), isFalse);
      expect(controller.hasUsageLimitFailure, isTrue);
      expect(controller.hasAutomaticRetry, isFalse);
      controller.dispose();
    },
  );

  test('retries a failed turn with the exact original submission', () async {
    final server = FakeCodexAppServer();
    final controller = await readyRetryController(server);
    controller
      ..selectedModelId = 'gpt-test'
      ..modelOptions = const [
        CodexModelOption(
          id: 'gpt-test',
          displayName: 'GPT Test',
          description: '',
          isDefault: true,
        ),
      ];
    const additionalInput = [
      {
        'type': 'skill',
        'name': 'documents',
        'path': '/skills/documents/SKILL.md',
      },
      {'type': 'localImage', 'path': '/tmp/reference.png'},
    ];
    const additionalContext = {
      'vscode': {
        'kind': 'application',
        'value': '{"activeFile":"/workspace/lib/main.dart"}',
      },
    };

    expect(
      await controller.sendPrompt(
        '修复断网重试',
        additionalInput: additionalInput,
        additionalContext: additionalContext,
        goal: '完成可靠重试',
        planMode: true,
        imagePaths: const ['/tmp/reference.png'],
      ),
      isTrue,
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {
            'status': 'failed',
            'error': {'message': 'network disconnected'},
          },
        },
      ),
    );

    expect(controller.hasFailedTurnRetry, isTrue);
    expect(controller.failedTurnRetryError, 'network disconnected');
    expect(await controller.retryFailedTurn(), isTrue);
    expect(server.startedTurnPrompts, ['修复断网重试', '修复断网重试']);
    expect(server.startedTurnAdditionalInput, additionalInput);
    expect(server.startedTurnAdditionalContext, additionalContext);
    expect(server.startedTurnCollaborationMode?['mode'], 'plan');
    expect(server.threadGoal, '完成可靠重试');
    expect(
      controller.entries.where((entry) => entry.kind == TimelineKind.user),
      hasLength(1),
    );
    expect(controller.hasFailedTurnRetry, isFalse);
    controller.dispose();
  });

  test(
    'blocks duplicate failed-turn retries while the first is pending',
    () async {
      final server = FakeCodexAppServer();
      final controller = await readyRetryController(server);
      expect(await controller.sendPrompt('重试一次'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'new-thread',
            'turn': {
              'status': 'failed',
              'error': {'message': 'offline'},
            },
          },
        ),
      );
      server.startTurnCompleter = Completer<void>();

      final firstRetry = controller.retryFailedTurn();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isRetryingFailedTurn, isTrue);
      expect(await controller.retryFailedTurn(), isFalse);
      expect(server.startedTurnPrompts, ['重试一次', '重试一次']);

      server.startTurnCompleter!.complete();
      expect(await firstRetry, isTrue);
      expect(controller.isRetryingFailedTurn, isFalse);
      controller.dispose();
    },
  );

  test(
    'keeps a failed retry available without contaminating a new task',
    () async {
      final server = FakeCodexAppServer();
      final controller = await readyRetryController(server);
      expect(await controller.sendPrompt('原任务'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'new-thread',
            'turn': {
              'status': 'failed',
              'error': {'message': 'offline'},
            },
          },
        ),
      );
      server
        ..startTurnCompleter = Completer<void>()
        ..startTurnError = StateError('still offline');

      final retry = controller.retryFailedTurn();
      await Future<void>.delayed(Duration.zero);
      controller.createThread();
      expect(controller.activeThreadId, isNull);
      server.startTurnCompleter!.complete();

      expect(await retry, isFalse);
      expect(controller.activeThreadId, isNull);
      expect(controller.status, RuntimeStatus.ready);
      expect(controller.lastError, isNull);
      expect(controller.hasFailedTurnRetry, isFalse);
      await controller.resumeThread(controller.threads.single);
      expect(controller.hasFailedTurnRetry, isTrue);
      expect(controller.failedTurnRetryError, contains('still offline'));
      controller.dispose();
    },
  );

  test(
    'keeps retry available when the repeated turn still cannot start',
    () async {
      final server = FakeCodexAppServer();
      final controller = await readyRetryController(server);
      expect(await controller.sendPrompt('继续重试'), isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'new-thread',
            'turn': {
              'status': 'failed',
              'error': {'message': 'offline'},
            },
          },
        ),
      );
      server.startTurnError = StateError('network still unavailable');

      expect(await controller.retryFailedTurn(), isFalse);
      expect(controller.hasFailedTurnRetry, isTrue);
      expect(
        controller.failedTurnRetryError,
        contains('network still unavailable'),
      );
      expect(controller.status, RuntimeStatus.ready);

      server.startTurnError = null;
      expect(await controller.retryFailedTurn(), isTrue);
      expect(controller.hasFailedTurnRetry, isFalse);
      controller.dispose();
    },
  );

  test('restores the previous turn diff when a retry start fails', () async {
    final server = FakeCodexAppServer();
    final controller = await readyRetryController(server);
    expect(await controller.sendPrompt('保留上一回合 Diff'), isTrue);

    const diff =
        'diff --git a/lib/main.dart b/lib/main.dart\n'
        '@@ -1 +1 @@\n'
        '-old\n'
        '+new';
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'lib/main.dart',
                'kind': 'modified',
                'diff': '@@ -1 +1 @@\n-old\n+new',
              },
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(method: 'turn/diff/updated', params: {'diff': diff}),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {
            'status': 'failed',
            'error': {'message': 'offline'},
          },
        },
      ),
    );
    expect(controller.turnDiff, diff);
    expect(controller.fileChanges.single.path, 'lib/main.dart');

    server.startTurnError = StateError('retry still offline');
    expect(await controller.retryFailedTurn(), isFalse);

    expect(controller.fileChanges.single.path, 'lib/main.dart');
    expect(controller.turnDiff, diff);
    expect(controller.failedTurnRetryError, 'retry still offline');
    controller.dispose();
  });

  test('does not offer retry after an interrupted turn', () async {
    final server = FakeCodexAppServer();
    final controller = await readyRetryController(server);
    expect(controller.canSend, isTrue);
    expect(await controller.sendPrompt('主动停止'), isTrue);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {'status': 'interrupted'},
        },
      ),
    );

    expect(controller.hasFailedTurnRetry, isFalse);
    expect(await controller.retryFailedTurn(), isFalse);
    controller.dispose();
  });
}
