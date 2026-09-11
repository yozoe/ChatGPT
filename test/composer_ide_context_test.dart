import 'dart:async';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_submission.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_fakes/fake_codex_app_server.dart';
import 'widget_fakes/fake_runtime_configuration_store.dart';

void main() {
  test('passes selected IDE context through turn steer', () async {
    final server = FakeCodexAppServer();
    final controller =
        CodexController(
            server: server,
            runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.running
          ..activeThreadId = 'thread-1'
          ..activeTurnId = 'turn-1';
    addTearDown(controller.dispose);
    const additionalContext = {
      'ide': {
        'kind': 'application',
        'value': '{"activeFile":{"path":"/workspace/lib/main.dart"}}',
      },
    };

    expect(
      await controller.steerCurrentTurn(
        '检查当前文件',
        additionalContext: additionalContext,
      ),
      isTrue,
    );
    expect(server.steeredTurnAdditionalContext, additionalContext);
  });

  testWidgets('sends selected IDE context through turn start only', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/ide_context_send_test');
    final bridge = CodexIdeContextBridge(channel: channel);
    final server = FakeCodexAppServer();
    final controller = CodexController(
      server: server,
      ideContextBridge: bridge,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..selectedModelId = 'gpt-test'
      ..modelOptions = const [
        CodexModelOption(
          id: 'gpt-test',
          displayName: 'GPT Test',
          description: '',
          isDefault: true,
        ),
      ];
    addTearDown(() {
      bridge.dispose();
    });
    await _sendHostUpdate(channel, const {
      'activeFile': {
        'path': '/workspace/lib/main.dart',
        'selectedText': 'runApp(App());',
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/IDE');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('composer-slash-command-workspaceContext')),
    );
    await tester.pump();
    await tester.enterText(field, '检查当前选区');
    await tester.tap(find.byTooltip('发送任务'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(server.startedTurnPrompt, '检查当前选区');
    expect(server.startedTurnAdditionalContext, {
      'ide': {
        'kind': 'application',
        'value':
            '{"activeFile":{"path":"/workspace/lib/main.dart","selectedText":"runApp(App());"},"openTabs":[]}',
      },
    });

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {'id': 'turn-1', 'status': 'completed'},
        },
      ),
    );
    await tester.pump();
    server.startedTurnAdditionalContext = const {'unexpected': true};
    await tester.enterText(field, '未选择上下文');
    await tester.tap(find.byTooltip('发送任务'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(server.startedTurnPrompt, '未选择上下文');
    expect(server.startedTurnAdditionalContext, isNull);
  });

  testWidgets('only submits IDE context after explicit selection', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/ide_context_composer_test');
    final bridge = CodexIdeContextBridge(channel: channel);
    final controller =
        CodexController(server: FakeCodexAppServer(), ideContextBridge: bridge)
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    final composer = TextEditingController();
    final submissions = <ComposerSubmission>[];
    addTearDown(() {
      composer.dispose();
      controller.dispose();
      bridge.dispose();
    });
    await _sendHostUpdate(channel, const {
      'activeFile': {'path': '/workspace/lib/main.dart'},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposerPanel(
            controller: controller,
            composer: composer,
            onSend: (submission) async {
              submissions.add(submission);
              return true;
            },
            onQueueSteer: (_) async => true,
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('composer-field')), '未选择');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submissions.single.includeIdeContext, isFalse);

    await tester.enterText(find.byKey(const Key('composer-field')), '/IDE');
    await tester.pump();
    final ideCommand = find.byKey(
      const ValueKey('composer-slash-command-workspaceContext'),
    );
    expect(tester.widget<InkWell>(ideCommand).onTap, isNotNull);
    expect(find.text('附加当前 IDE 文件、选区和打开标签'), findsOneWidget);
    await tester.tap(ideCommand);
    await tester.pump();
    expect(find.byKey(const Key('composer-ide-context-chip')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('composer-field')), '检查选区');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submissions.last.includeIdeContext, isTrue);
    expect(find.byKey(const Key('composer-ide-context-chip')), findsNothing);

    await tester.enterText(find.byKey(const Key('composer-field')), '/IDE');
    await tester.pump();
    await tester.tap(ideCommand);
    await tester.pump();
    expect(find.byKey(const Key('composer-ide-context-chip')), findsOneWidget);
    controller.workspacePath = '/other-workspace';
    await _sendHostUpdate(channel, const {
      'activeFile': {'path': '/other-workspace/lib/main.dart'},
    });
    await tester.pump();
    expect(find.byKey(const Key('composer-ide-context-chip')), findsNothing);

    controller.workspacePath = '/workspace';
    await tester.enterText(find.byKey(const Key('composer-field')), '/IDE');
    await tester.pump();
    await tester.tap(ideCommand);
    await tester.pump();
    expect(find.byKey(const Key('composer-ide-context-chip')), findsOneWidget);
    await _sendHostUpdate(channel, const {});
    await tester.pump();
    expect(find.byKey(const Key('composer-ide-context-chip')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _sendHostUpdate(MethodChannel channel, Object arguments) async {
  final response = Completer<ByteData?>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('updateContext', arguments)),
        response.complete,
      );
  await response.future;
}
