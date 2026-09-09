import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preserves the historical provider when resuming a thread', () async {
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.resumeThread(
      protocolThread(
        id: 'openai-thread',
        modelProvider: 'openai',
        model: 'gpt-5',
      ),
    );

    expect(server.resumedThreadId, 'openai-thread');
    expect(server.resumedModelProvider, 'openai');
    expect(server.resumedModel, 'gpt-5');
    expect(server.resumedConfig, isNull);
    controller.dispose();
  });

  test('restores a persisted goal when reopening a thread', () async {
    final server = FakeCodexAppServer()
      ..threadGoalResponse = {
        'threadId': 'goal-thread',
        'objective': '完成跨会话目标',
        'status': 'paused',
        'tokenBudget': 2000,
        'tokensUsed': 500,
        'timeUsedSeconds': 90,
      };
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.resumeThread(protocolThread(id: 'goal-thread'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.activeThreadGoal?.objective, '完成跨会话目标');
    expect(controller.activeThreadGoal?.status, 'paused');
    expect(controller.activeThreadGoal?.progress, 0.25);
    controller.dispose();
  });

  test('uses the authoritative goal returned by a lifecycle update', () async {
    final server = FakeCodexAppServer()
      ..threadGoalResponse = {
        'threadId': 'goal-thread',
        'objective': '原目标',
        'status': 'active',
        'tokenBudget': 2000,
        'tokensUsed': 500,
        'timeUsedSeconds': 120,
      }
      ..threadGoalSetResponse = {
        'threadId': 'goal-thread',
        'objective': '更新后的目标',
        'status': 'paused',
        'tokenBudget': null,
        'tokensUsed': 750,
        'timeUsedSeconds': 180,
      };
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await controller.resumeThread(protocolThread(id: 'goal-thread'));
    await Future<void>.delayed(Duration.zero);

    expect(await controller.editActiveGoal('本地输入'), isTrue);

    expect(controller.activeThreadGoal?.objective, '更新后的目标');
    expect(controller.activeThreadGoal?.status, 'paused');
    expect(controller.activeThreadGoal?.tokenBudget, isNull);
    expect(controller.activeThreadGoal?.tokensUsed, 750);
    expect(controller.activeThreadGoal?.timeUsedSeconds, 180);
    controller.dispose();
  });

  test(
    'does not silently downgrade plan mode without a resolved model',
    () async {
      final server = FakeCodexAppServer();
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      controller
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      expect(await controller.sendPrompt('先制定计划', planMode: true), isFalse);

      expect(server.startedTurnPrompt, isNull);
      expect(controller.lastError, contains('读取可用模型'));
      controller.dispose();
    },
  );

  test('passes every workspace root only when creating a new thread', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-thread-roots-',
    );
    addTearDown(() => root.delete(recursive: true));
    final primary = await Directory(
      '${root.path}/primary',
    ).create(recursive: true);
    final additional = await Directory(
      '${root.path}/additional',
    ).create(recursive: true);
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    await controller.selectWorkspace(primary.path);
    await controller.addWorkspaceRoot(additional.path);
    controller.status = RuntimeStatus.ready;

    await controller.sendPrompt('读取两个目录');

    expect(server.startedThreadDirectory, await primary.resolveSymbolicLinks());
    expect(server.startedRuntimeWorkspaceRoots, [
      await primary.resolveSymbolicLinks(),
      await additional.resolveSymbolicLinks(),
    ]);

    controller
      ..status = RuntimeStatus.ready
      ..activeThreadId = null;
    await controller.resumeThread(protocolThread(id: 'historical-thread'));
    expect(server.resumedThreadId, 'historical-thread');
    controller.dispose();
  });

  test('encodes runtime workspace roots in the thread start request', () async {
    final server = ProtocolCaptureCodexAppServer();
    final threadId = await server.startThread(
      workingDirectory: '/primary',
      runtimeWorkspaceRoots: const ['/primary', '/shared'],
    );

    expect(server.requestedMethod, 'thread/start');
    expect(server.requestedParams, {
      'cwd': '/primary',
      'runtimeWorkspaceRoots': ['/primary', '/shared'],
    });
    expect(threadId, 'thread-with-roots');
  });

  test('encodes composer context in the turn start request', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.startTurn(
      threadId: 'thread-1',
      prompt: r'$documents Review this image',
      workingDirectory: '/workspace',
      additionalInput: const [
        {'type': 'localImage', 'path': '/tmp/design.png'},
        {
          'type': 'skill',
          'name': 'documents',
          'path': '/skills/documents/SKILL.md',
        },
      ],
      collaborationMode: const {
        'mode': 'plan',
        'settings': {
          'model': 'gpt-test',
          'reasoning_effort': null,
          'developer_instructions': null,
        },
      },
    );

    expect(server.requestedMethod, 'turn/start');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'cwd': '/workspace',
      'input': [
        {'type': 'text', 'text': r'$documents Review this image'},
        {'type': 'localImage', 'path': '/tmp/design.png'},
        {
          'type': 'skill',
          'name': 'documents',
          'path': '/skills/documents/SKILL.md',
        },
      ],
      'collaborationMode': {
        'mode': 'plan',
        'settings': {
          'model': 'gpt-test',
          'reasoning_effort': null,
          'developer_instructions': null,
        },
      },
    });
  });

  test('encodes active-turn direction adjustments', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.steerTurn(
      threadId: 'thread-1',
      expectedTurnId: 'turn-1',
      prompt: '改成灰色',
      additionalInput: const [
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ],
    );

    expect(server.requestedMethod, 'turn/steer');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'expectedTurnId': 'turn-1',
      'input': [
        {'type': 'text', 'text': '改成灰色'},
        {'type': 'localImage', 'path': '/tmp/steer.png'},
      ],
    });
  });

  test('encodes both thread and turn IDs when interrupting a turn', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.interruptTurn(threadId: 'thread-1', turnId: 'turn-1');

    expect(server.requestedMethod, 'turn/interrupt');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'turnId': 'turn-1',
    });
  });

  test('encodes goal lifecycle operations', () async {
    final server = ProtocolCaptureCodexAppServer();

    await server.updateThreadGoal(
      threadId: 'thread-1',
      objective: '完成迁移',
      status: 'paused',
    );
    expect(server.requestedMethod, 'thread/goal/set');
    expect(server.requestedParams, {
      'threadId': 'thread-1',
      'objective': '完成迁移',
      'status': 'paused',
    });

    await server.clearThreadGoal(threadId: 'thread-1');
    expect(server.requestedMethod, 'thread/goal/clear');
    expect(server.requestedParams, {'threadId': 'thread-1'});
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
