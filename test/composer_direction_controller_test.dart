import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/conversation_attachment_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

CodexThread directionTestThread({
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

Future<void> waitForPendingDirectionSendToSettle(
  CodexController controller,
) async {
  var observedSending = false;
  for (var attempt = 0; attempt < 200; attempt++) {
    observedSending = observedSending || controller.pendingTurnSteerSending;
    if (observedSending && !controller.pendingTurnSteerSending) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryConversationHistoryStore historyStore;
  late FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    historyStore = MemoryConversationHistoryStore();
    runtimeConfigurationStore = FakeRuntimeConfigurationStore();
    CodexController.testingConversationHistoryStore = historyStore;
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  test('adjusts the active turn direction through the App Server', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    final sent = await controller.steerCurrentTurn(
      '改成灰色',
      additionalInput: const [
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ],
    );

    expect(sent, isTrue);
    expect(server.steeredTurnThreadId, 'thread-1');
    expect(server.steeredTurnId, 'turn-1');
    expect(server.steeredTurnPrompt, '改成灰色');
    expect(server.steeredTurnAdditionalInput, [
      {'type': 'localImage', 'path': '/tmp/steer.png'},
    ]);
    expect(controller.entries.any((entry) => entry.detail == '改成灰色'), isTrue);
    controller.dispose();
  });

  test('retains the turn id returned by steering', () async {
    final server = FakeCodexAppServer()..steerResponseTurnId = 'turn-2';
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';

    expect(await controller.steerCurrentTurn('继续'), isTrue);
    expect(controller.activeTurnId, 'turn-2');
    controller.dispose();
  });

  test(
    'keeps streaming reply indexes after inserting an accepted direction',
    () async {
      final steerCompleter = Completer<String>();
      final server = FakeCodexAppServer()..steerCompleter = steerCompleter;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';

      final steer = controller.steerCurrentTurn('继续，但换个方向');
      await Future<void>.delayed(Duration.zero);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reply-after-steer',
            'delta': '后续',
          },
        ),
      );
      steerCompleter.complete('turn-1');
      expect(await steer, isTrue);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reply-after-steer',
            'delta': '回复',
          },
        ),
      );

      final reply = controller.entries.singleWhere(
        (entry) => entry.sourceItemId == null && entry.detail == '后续回复',
      );
      final direction = controller.entries.singleWhere(
        (entry) => entry.kind == TimelineKind.user,
      );
      expect(
        controller.entries.indexOf(direction),
        lessThan(controller.entries.indexOf(reply)),
      );
      controller.dispose();
    },
  );

  test(
    'does not write an in-flight direction into a newly opened task',
    () async {
      final steerCompleter = Completer<String>();
      final server = FakeCodexAppServer()..steerCompleter = steerCompleter;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '旧任务方向', prompt: '旧任务方向'),
      );

      final send = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);
      expect(server.steeredTurnPrompt, '旧任务方向');

      controller.createThread();
      steerCompleter.complete('turn-1');

      expect(await send, isTrue);
      expect(controller.activeThreadId, isNull);
      expect(controller.pendingTurnSteer, isNull);
      expect(
        controller.entries.map((entry) => entry.detail),
        isNot(contains('旧任务方向')),
      );
      controller.dispose();
    },
  );

  test(
    'does not duplicate a delayed direction after switching away and back',
    () async {
      final steerCompleter = Completer<String>();
      final server = FakeCodexAppServer()
        ..steerCompleter = steerCompleter
        ..turnPage = {
          'data': [
            {
              'id': 'turn-1',
              'status': 'inProgress',
              'items': [
                {
                  'id': 'direction-item',
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': '切回后不要重复'},
                  ],
                },
                {
                  'id': 'agent-item',
                  'type': 'agentMessage',
                  'text': '历史中的后续回复',
                },
              ],
            },
          ],
        };
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-a'
        ..activeTurnId = 'turn-1'
        ..threads = [
          directionTestThread(id: 'thread-a', status: 'active'),
          directionTestThread(id: 'thread-b'),
        ];

      final steer = controller.steerCurrentTurn('切回后不要重复');
      await Future<void>.delayed(Duration.zero);
      await controller.resumeThread(directionTestThread(id: 'thread-b'));
      await controller.resumeThread(
        directionTestThread(id: 'thread-a', status: 'active'),
      );
      steerCompleter.complete('turn-1');

      expect(await steer, isTrue);
      final details = controller.entries.map((entry) => entry.detail).toList();
      expect(details.where((detail) => detail == '切回后不要重复'), hasLength(1));
      expect(details.indexOf('切回后不要重复'), lessThan(details.indexOf('历史中的后续回复')));
      controller.dispose();
    },
  );

  test(
    'does not release a newer direction send when an older send finishes',
    () async {
      final firstCompleter = Completer<String>();
      final secondCompleter = Completer<String>();
      final server = FakeCodexAppServer()..steerCompleter = firstCompleter;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '旧任务方向', prompt: '旧任务方向'),
      );
      final firstSend = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);

      controller.createThread();
      server.steerCompleter = secondCompleter;
      controller
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-2'
        ..activeTurnId = 'turn-2';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '新任务方向', prompt: '新任务方向'),
      );
      final secondSend = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);

      firstCompleter.complete('turn-1');
      expect(await firstSend, isTrue);
      expect(controller.pendingTurnSteer?.prompt, '新任务方向');
      expect(controller.pendingTurnSteerSending, isTrue);
      expect(
        controller.entries.map((entry) => entry.detail),
        isNot(contains('旧任务方向')),
      );

      secondCompleter.complete('turn-2');
      expect(await secondSend, isTrue);
      expect(controller.pendingTurnSteer, isNull);
      expect(controller.pendingTurnSteerSending, isFalse);
      expect(
        controller.entries.map((entry) => entry.detail),
        contains('新任务方向'),
      );
      controller.dispose();
    },
  );

  test(
    'does not write a stale direction failure into a newly opened task',
    () async {
      final steerCompleter = Completer<String>();
      final server = FakeCodexAppServer()..steerCompleter = steerCompleter;
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '旧任务方向', prompt: '旧任务方向'),
      );

      final send = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);
      controller.createThread();
      steerCompleter.completeError(StateError('stale failure'));

      expect(await send, isFalse);
      expect(controller.activeThreadId, isNull);
      expect(controller.lastError, isNull);
      expect(
        controller.entries.map((entry) => entry.title),
        isNot(contains('调整方向失败')),
      );
      controller.dispose();
    },
  );

  test(
    'sends a queued direction as a new turn after the active turn completes',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'thread-1', 'status': 'idle'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '完成后继续处理', prompt: '完成后继续处理'),
      );

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-1',
            'turn': {'status': 'completed'},
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(server.startedTurnThreadId, 'thread-1');
      expect(server.startedTurnPrompt, '完成后继续处理');
      expect(controller.pendingTurnSteer, isNull);
      expect(controller.status, RuntimeStatus.running);
      controller.dispose();
    },
  );

  test(
    'does not auto-send while an explicit direction adjustment is pending',
    () async {
      final steerCompleter = Completer<String>();
      final server = FakeCodexAppServer()
        ..steerCompleter = steerCompleter
        ..listResponse = [
          {'id': 'thread-1', 'status': 'idle'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(
          displayText: '只发送一次',
          prompt: '只发送一次',
          additionalInput: [
            {'type': 'localImage', 'path': '/tmp/steer-race.png'},
          ],
          imagePaths: ['/tmp/steer-race.png'],
        ),
      );

      final steer = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-1',
            'turn': {'status': 'completed'},
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(server.startedTurnPrompt, isNull);
      steerCompleter.complete('turn-2');
      expect(await steer, isTrue);
      expect(server.steeredTurnPrompt, '只发送一次');
      final acceptedDirection = controller.entries.singleWhere(
        (entry) => entry.kind == TimelineKind.user && entry.detail == '只发送一次',
      );
      expect(acceptedDirection.imagePaths, ['/tmp/steer-race.png']);
      final directionIndex = controller.entries.indexOf(acceptedDirection);
      final completionIndex = controller.entries.indexWhere(
        (entry) => entry.title == '任务完成',
      );
      expect(completionIndex, greaterThanOrEqualTo(0));
      expect(directionIndex, lessThan(completionIndex));
      controller.dispose();
    },
  );

  test(
    'sends the pending direction as a new turn when explicit steering loses the completion race',
    () async {
      final steerCompleter = Completer<String>();
      final server = FakeCodexAppServer()
        ..steerCompleter = steerCompleter
        ..listResponse = [
          {'id': 'thread-1', 'status': 'idle'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(displayText: '下一轮继续', prompt: '下一轮继续'),
      );

      final steer = controller.sendPendingTurnSteer();
      await Future<void>.delayed(Duration.zero);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-1',
            'turn': {'status': 'completed'},
          },
        ),
      );
      steerCompleter.completeError(StateError('turn already completed'));

      expect(await steer, isTrue);
      expect(server.startedTurnThreadId, 'thread-1');
      expect(server.startedTurnPrompt, '下一轮继续');
      expect(controller.pendingTurnSteer, isNull);
      controller.dispose();
    },
  );

  test(
    'persists a queued direction goal before steering the active turn',
    () async {
      final server = FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      controller.queueTurnSteer(
        const PendingTurnSteer(
          displayText: '继续处理附件',
          prompt: '继续处理附件',
          goal: '完成附件菜单',
        ),
      );

      expect(await controller.sendPendingTurnSteer(), isTrue);
      expect(server.threadGoal, '完成附件菜单');
      expect(server.steeredTurnPrompt, '继续处理附件');
      controller.dispose();
    },
  );

  test(
    'auto-sends queued directions in order across completed turns',
    () async {
      final server = FakeCodexAppServer()
        ..listResponse = [
          {'id': 'thread-1', 'status': 'idle'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      for (final message in ['第一条', '第二条']) {
        controller.queueTurnSteer(
          PendingTurnSteer(displayText: message, prompt: message),
        );
      }

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-1',
            'turn': {'id': 'turn-1', 'status': 'completed'},
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.startedTurnPrompt, '第一条');
      expect(controller.pendingTurnSteers.single.prompt, '第二条');
      await waitForPendingDirectionSendToSettle(controller);

      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-1',
            'turn': {'id': controller.activeTurnId, 'status': 'completed'},
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.startedTurnPrompt, '第二条');
      expect(controller.pendingTurnSteers, isEmpty);
      controller.dispose();
    },
  );

  test(
    'restores the queue without a duplicate user entry when auto-send fails',
    () async {
      final server = FakeCodexAppServer()
        ..startTurnError = StateError('turn rejected')
        ..listResponse = [
          {'id': 'thread-1', 'status': 'idle'},
        ];
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-1'
        ..activeTurnId = 'turn-1';
      for (final message in ['第一条', '第二条']) {
        controller.queueTurnSteer(
          PendingTurnSteer(displayText: message, prompt: message),
        );
      }

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-1',
            'turn': {'id': 'turn-1', 'status': 'completed'},
          },
        ),
      );
      for (var attempt = 0; attempt < 100; attempt++) {
        if (controller.entries.any((entry) => entry.title == '任务未能启动')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(controller.pendingTurnSteers.map((item) => item.prompt), [
        '第一条',
        '第二条',
      ]);
      expect(
        controller.entries.where(
          (entry) => entry.kind == TimelineKind.user && entry.detail == '第一条',
        ),
        isEmpty,
      );
      expect(
        controller.entries.map((entry) => entry.title),
        contains('任务未能启动'),
      );
      controller.dispose();
    },
  );

  test(
    'retains a temporary steering image when completion races the acknowledgement',
    () async {
      const channel = MethodChannel('codex_desk/clipboard');
      final sourceFile = await File(
        '${Directory.systemTemp.path}/codex-desk-steer-race.png',
      ).create();
      await sourceFile.writeAsBytes(<int>[137, 80, 78, 71]);
      final imagePath = sourceFile.path;
      addTearDown(() async {
        if (await sourceFile.exists()) await sourceFile.delete();
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var deleteCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'readFileItems':
            return [
              {'path': imagePath, 'isDirectory': false, 'isTemporary': true},
            ];
          case 'deleteTemporaryItem':
            deleteCalls++;
            return true;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final steerCompleter = Completer<String>();
      final server = FakeCodexAppServer()..steerCompleter = steerCompleter;
      final attachmentDirectory = await Directory.systemTemp.createTemp(
        'codex-desk-steer-attachments-',
      );
      addTearDown(() => attachmentDirectory.delete(recursive: true));
      final controller =
          CodexController(
              server: server,
              conversationAttachmentStore: ConversationAttachmentStore(
                directory: attachmentDirectory,
              ),
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.running
            ..activeThreadId = 'thread-1'
            ..activeTurnId = 'turn-1';
      controller.retainTemporaryAttachment(imagePath);
      final steer = controller.steerCurrentTurn(
        '按截图调整',
        additionalInput: [
          {'type': 'localImage', 'path': imagePath},
        ],
        imagePaths: [imagePath],
      );
      await server.steerEntered.future;
      expect(server.steeredTurnPrompt, '按截图调整');

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'thread-1',
            'turn': {'id': 'turn-1', 'status': 'completed'},
          },
        ),
      );
      expect(deleteCalls, 0);

      steerCompleter.complete('turn-2');
      expect(await steer, isTrue);

      final acceptedDirection = controller.entries.singleWhere(
        (entry) => entry.kind == TimelineKind.user && entry.detail == '按截图调整',
      );
      expect(acceptedDirection.imagePaths, hasLength(1));
      final durableImagePath = acceptedDirection.imagePaths.single;
      expect(durableImagePath, isNot(imagePath));
      expect(await File(durableImagePath).exists(), isTrue);
      expect(deleteCalls, 0);

      controller.dispose();
      expect(deleteCalls, 1);
    },
  );
}
