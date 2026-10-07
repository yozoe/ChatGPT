import 'dart:async';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

CodexThread protocolThread({
  required String id,
  String? modelProvider,
  String? model,
}) => CodexThread(
  id: id,
  preview: 'preview-$id',
  createdAt: 1,
  updatedAt: 2,
  modelProvider: modelProvider,
  model: model,
);

ServerEvent tokenUsageEvent({
  required String threadId,
  required String turnId,
  required int usedTokens,
  required int totalTokens,
  Object? maximumTokens = 100000,
}) => ServerEvent(
  method: 'thread/tokenUsage/updated',
  params: {
    'threadId': threadId,
    'turnId': turnId,
    'tokenUsage': {
      'last': {'totalTokens': usedTokens},
      'total': {'totalTokens': totalTokens},
      'modelContextWindow': maximumTokens,
    },
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts compaction as a real active App Server turn', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await controller.resumeThread(protocolThread(id: 'thread-1'));

    expect(await controller.compactActiveThread(), isTrue);

    expect(server.compactedThreadId, 'thread-1');
    expect(controller.status, RuntimeStatus.running);
    controller.dispose();
  });

  test('cleans up failed compaction after switching tasks', () async {
    final completer = Completer<void>();
    final server = FakeCodexAppServer()..compactThreadCompleter = completer;
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [
        protocolThread(id: 'thread-1'),
        protocolThread(id: 'thread-2'),
      ];
    await controller.resumeThread(controller.threads.first);

    final compaction = controller.compactActiveThread();
    await Future<void>.delayed(Duration.zero);
    await controller.resumeThread(protocolThread(id: 'thread-2'));
    server.compactThreadError = StateError('compaction failed');
    completer.complete();

    expect(await compaction, isFalse);
    expect(controller.activeThreadId, 'thread-2');
    expect(controller.isThreadRunning('thread-1'), isFalse);
    expect(controller.status, RuntimeStatus.ready);
    controller.dispose();
  });

  test('starts a structured review from a blank workspace chat', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    expect(
      await controller.startCodeReview(const {'type': 'uncommittedChanges'}),
      isTrue,
    );

    expect(controller.activeThreadId, 'new-thread');
    expect(server.startedReviewThreadId, 'new-thread');
    expect(server.startedReviewTarget, {'type': 'uncommittedChanges'});
    expect(controller.activeTurnId, 'review-turn');
    controller.dispose();
  });

  test('cleans up a failed review after switching tasks', () async {
    final completer = Completer<void>();
    final server = FakeCodexAppServer()..startReviewCompleter = completer;
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [
        protocolThread(id: 'thread-1'),
        protocolThread(id: 'thread-2'),
      ];
    await controller.resumeThread(controller.threads.first);

    final review = controller.startCodeReview(const {
      'type': 'uncommittedChanges',
    });
    await Future<void>.delayed(Duration.zero);
    await controller.resumeThread(protocolThread(id: 'thread-2'));
    server.startReviewError = StateError('review failed');
    completer.complete();

    expect(await review, isFalse);
    expect(controller.activeThreadId, 'thread-2');
    expect(controller.isThreadRunning('thread-1'), isFalse);
    expect(controller.status, RuntimeStatus.ready);
    controller.dispose();
  });

  test('submits feedback only with the selected log preference', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    )..activeThreadId = 'thread-1';

    expect(
      await controller.submitFeedback(
        classification: 'bug',
        includeLogs: false,
        reason: 'Composer issue',
      ),
      isTrue,
    );

    expect(server.feedbackClassification, 'bug');
    expect(server.feedbackIncludeLogs, isFalse);
    expect(server.feedbackReason, 'Composer issue');
    expect(server.feedbackThreadId, 'thread-1');
    controller.dispose();
  });

  test('opts into experimental App Server fields during initialize', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.initialize();

    expect(server.requestedMethod, 'initialize');
    expect(server.requestedParams, {
      'clientInfo': {
        'name': 'chatgpt_flutter',
        'title': 'Codex Desk',
        'version': '0.1.0',
      },
      'capabilities': {
        'experimentalApi': true,
        'mcpServerOpenaiFormElicitation': true,
      },
    });
    expect(server.notifications, ['initialized']);
  });
}
