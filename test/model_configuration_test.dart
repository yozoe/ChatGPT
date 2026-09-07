import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

CodexThread modelConfigurationThread({required String id, String? model}) =>
    CodexThread(
      id: id,
      preview: 'preview-$id',
      createdAt: 1,
      updatedAt: 2,
      model: model,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applies selected model and effort only to new threads', () async {
    final store = FakeRuntimeConfigurationStore();
    final server = FakeCodexAppServer()
      ..modelListResponse = [
        {
          'id': 'gpt-5',
          'model': 'gpt-5',
          'isDefault': true,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'low'},
            {'reasoningEffort': 'high'},
          ],
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: store,
    );
    await controller.waitForInitialConfiguration();
    await controller.refreshReasoningEffortCapabilitiesForTesting();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await controller.setModel('gpt-5');
    await controller.setReasoningEffort(ReasoningEffort.high);
    await controller.sendPrompt('开始新任务');

    expect(store.savedModel, 'gpt-5');
    expect(store.savedReasoningEffort, 'high');
    expect(server.startedModelProvider, isNull);
    expect(server.startedModel, 'gpt-5');
    expect(server.startedConfig, {'model_reasoning_effort': 'high'});

    controller
      ..activeThreadId = null
      ..status = RuntimeStatus.ready;
    await controller.resumeThread(
      modelConfigurationThread(id: 'openai-thread', model: 'historical-model'),
    );

    expect(server.resumedModel, 'historical-model');
    expect(server.resumedConfig, isNull);
    controller.dispose();
  });

  test('switching models updates supported reasoning strengths', () async {
    final store = FakeRuntimeConfigurationStore();
    final server = FakeCodexAppServer()
      ..modelListResponse = [
        {
          'id': 'deep-model',
          'model': 'deep-model',
          'displayName': 'Deep model',
          'isDefault': true,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'high'},
          ],
        },
        {
          'id': 'fast-model',
          'model': 'fast-model',
          'displayName': 'Fast model',
          'isDefault': false,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'low'},
          ],
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: store,
    );

    await controller.waitForInitialConfiguration();
    await controller.refreshReasoningEffortCapabilitiesForTesting();
    await controller.setReasoningEffort(ReasoningEffort.high);
    await controller.setModel('fast-model');

    expect(controller.selectedModelId, 'fast-model');
    expect(controller.selectedModelLabel, 'Fast model');
    expect(store.savedModel, 'fast-model');
    expect(controller.reasoningEffort, ReasoningEffort.defaultValue);
    expect(controller.reasoningEffortOptions, [
      ReasoningEffort.defaultValue,
      ReasoningEffort.low,
    ]);
    expect(store.savedReasoningEffort, isNull);

    await controller.setModel(null);

    expect(controller.selectedModelId, isNull);
    expect(store.savedModel, isNull);
    expect(controller.reasoningEffortOptions, [
      ReasoningEffort.defaultValue,
      ReasoningEffort.high,
    ]);
    controller.dispose();
  });

  test('only exposes strengths supported by the default model', () async {
    final store = FakeRuntimeConfigurationStore()..reasoningEffort = 'high';
    final server = FakeCodexAppServer()
      ..modelListResponse = [
        {
          'id': 'gpt-5',
          'model': 'gpt-5',
          'isDefault': true,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'low'},
          ],
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: store,
    );

    await controller.waitForInitialConfiguration();
    expect(controller.reasoningEffort, ReasoningEffort.high);
    await controller.refreshReasoningEffortCapabilitiesForTesting();

    expect(controller.reasoningEffort, ReasoningEffort.defaultValue);
    expect(controller.reasoningEffortOptions, [
      ReasoningEffort.defaultValue,
      ReasoningEffort.low,
    ]);
    controller.dispose();
  });

  test('preserves newly advertised reasoning effort values', () async {
    final store = FakeRuntimeConfigurationStore();
    final server = FakeCodexAppServer()
      ..modelListResponse = [
        {
          'id': 'future-model',
          'model': 'future-model',
          'isDefault': true,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'ultra'},
          ],
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: store,
    );
    await controller.waitForInitialConfiguration();
    await controller.refreshReasoningEffortCapabilitiesForTesting();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    final ultra = controller.reasoningEffortOptions.singleWhere(
      (effort) => effort.configValue == 'ultra',
    );
    await controller.setReasoningEffort(ultra);
    await controller.sendPrompt('使用新推理强度');

    expect(ultra.label, 'ultra');
    expect(store.savedReasoningEffort, 'ultra');
    expect(server.startedConfig, {'model_reasoning_effort': 'ultra'});
    controller.dispose();
  });

  test(
    'blocks unresolved saved selections when catalog loading fails',
    () async {
      final store = FakeRuntimeConfigurationStore()
        ..model = 'saved-model'
        ..reasoningEffort = 'high';
      final controller = CodexController(
        server: FakeCodexAppServer()
          ..modelListError = StateError('catalog unavailable'),
        runtimeConfigurationStore: store,
      );
      await controller.waitForInitialConfiguration();
      await controller.refreshReasoningEffortCapabilitiesForTesting();
      controller
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;

      expect(controller.selectedModelLabel, 'saved-model');
      expect(controller.modelSelectionError, contains('catalog unavailable'));
      expect(controller.canSend, isFalse);

      await controller.setModel(null);
      await controller.setReasoningEffort(ReasoningEffort.defaultValue);

      expect(controller.modelSelectionError, isNull);
      expect(controller.canSend, isTrue);
      controller.dispose();
    },
  );

  test(
    'clears runtime-resolved configuration when switching projects',
    () async {
      final firstWorkspace = await Directory.systemTemp.createTemp(
        'codex-config-first-',
      );
      final secondWorkspace = await Directory.systemTemp.createTemp(
        'codex-config-second-',
      );
      addTearDown(() => firstWorkspace.delete(recursive: true));
      addTearDown(() => secondWorkspace.delete(recursive: true));
      final server = FakeCodexAppServer()
        ..configReadResponse = {
          'config': {
            'model': 'project-model',
            'model_provider': 'project-provider',
          },
          'origins': <String, Object?>{},
        }
        ..modelListResponse = [
          {
            'id': 'project-model',
            'model': 'project-model',
            'isDefault': true,
            'supportedReasoningEfforts': <Object?>[],
          },
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      controller.workspacePath = firstWorkspace.path;
      await controller.refreshCodexConfiguration();
      await controller.refreshReasoningEffortCapabilitiesForTesting();

      expect(controller.configuredModelLabel, 'project-model');
      expect(controller.providerLabel, 'project-provider');
      expect(controller.modelOptions, isNotEmpty);

      await controller.selectWorkspace(secondWorkspace.path);

      expect(controller.codexConfigurationRead, isFalse);
      expect(controller.configuredModelLabel, '等待读取运行时配置');
      expect(controller.providerLabel, 'Codex 配置');
      expect(controller.modelOptions, isEmpty);
      controller.dispose();
    },
  );
}
