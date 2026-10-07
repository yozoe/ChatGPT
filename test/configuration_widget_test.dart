import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  testWidgets('shows Codex configuration without provider input fields', (
    tester,
  ) async {
    final server = FakeCodexAppServer()
      ..configReadResponse = {
        'config': {'model': 'gpt-5.6-sol', 'model_provider': 'company-relay'},
        'origins': {
          'model': {
            'name': {'type': 'project', 'dotCodexFolder': '/workspace/.codex'},
            'version': '1',
          },
          'model_provider': {
            'name': {'type': 'user', 'file': '/Users/test/.codex/config.toml'},
            'version': '1',
          },
        },
      };
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('codex-configuration-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('codex-configuration-dialog')), findsOneWidget);
    expect(find.byKey(const Key('codex-configuration-path')), findsOneWidget);
    expect(find.text('已从 Codex 运行时读取'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('codex-configuration-dialog')),
        matching: find.text('gpt-5.6-sol'),
      ),
      findsOneWidget,
    );
    expect(find.text('company-relay'), findsWidgets);
    expect(find.text('来源：/workspace/.codex/config.toml'), findsOneWidget);
    expect(find.text('来源：/Users/test/.codex/config.toml'), findsOneWidget);
    expect(server.configReadDirectory, '/workspace');
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('模型名称'), findsNothing);
    expect(find.text('中转站 API Key'), findsNothing);
    expect(find.textContaining('本应用不再单独收集或保存这些字段'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switches the new-task model and updates the reasoning menu', (
    tester,
  ) async {
    final server = FakeCodexAppServer()
      ..modelListResponse = [
        {
          'id': 'deep-model',
          'model': 'deep-model',
          'displayName': 'deep-model',
          'isDefault': true,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'high'},
          ],
        },
        {
          'id': 'fast-model',
          'model': 'fast-model',
          'displayName': 'fast-model',
          'isDefault': false,
          'supportedReasoningEfforts': [
            {'reasoningEffort': 'low'},
          ],
        },
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    await controller.refreshReasoningEffortCapabilitiesForTesting();
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('composer-model-controls')), findsOneWidget);
    expect(
      find.byKey(const Key('composer-context-usage-button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('composer-context-usage-button')));
    await tester.pumpAndSettle();
    expect(find.text('背景信息窗口：'), findsOneWidget);
    expect(find.text('正在等待 Codex 返回上下文用量'), findsOneWidget);
    expect(find.textContaining('发送任务后，此处会显示运行时报告的真实用量。'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pump();
    final composerField = tester.widget<TextField>(
      find.byKey(const Key('composer-field')),
    );
    final composerDecoration = composerField.decoration!;
    expect(composerDecoration.border, InputBorder.none);
    expect(composerDecoration.enabledBorder, InputBorder.none);
    expect(composerDecoration.focusedBorder, InputBorder.none);
    final modelControls = tester.widget<Container>(
      find.byKey(const Key('composer-model-controls')),
    );
    expect((modelControls.decoration! as BoxDecoration).border, isNull);
    await tester.tap(find.byKey(const Key('model-selector')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('model-option-follow-config')),
        matching: find.text('默认'),
      ),
      findsOneWidget,
    );
    expect(find.text('fast-model'), findsOneWidget);
    expect(find.text('新任务模型：fast-model'), findsNothing);
    expect(find.textContaining('fast-model ·'), findsNothing);
    final fastModelItem = find.byKey(const Key('model-option-fast-model'));
    await tester.tapAt(tester.getTopLeft(fastModelItem) + const Offset(12, 12));
    await tester.pumpAndSettle();

    expect(controller.selectedModelId, 'fast-model');
    expect(controller.reasoningEffortOptions, [
      ReasoningEffort.defaultValue,
      ReasoningEffort.low,
    ]);

    await tester.tap(find.byKey(const Key('reasoning-effort-selector')));
    await tester.pumpAndSettle();
    expect(find.text('低'), findsOneWidget);
    expect(find.text('新任务推理强度：低'), findsNothing);
    expect(find.text('高'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
