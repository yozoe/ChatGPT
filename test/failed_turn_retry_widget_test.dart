import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  testWidgets('renders a usage-limit notice with usage-dashboard action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    expect(await tester.runAsync(() => controller.sendPrompt('额度界面')), isTrue);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {
            'status': 'failed',
            'error': {'message': "You've hit your usage limit."},
          },
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('usage-limit-notice')), findsOneWidget);
    expect(find.byKey(const Key('usage-limit-open-button')), findsOneWidget);
    expect(find.byKey(const Key('usage-limit-retry-button')), findsOneWidget);
    expect(find.text('额度恢复后重试'), findsOneWidget);
    expect(find.byKey(const Key('failed-turn-retry-notice')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows an inline retry action for a failed turn', (tester) async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    expect(await tester.runAsync(() => controller.sendPrompt('网络测试')), isTrue);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {
            'status': 'failed',
            'error': {'message': '连接已断开'},
          },
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('failed-turn-retry-notice')), findsOneWidget);
    expect(find.text('连接已断开'), findsWidgets);
    expect(find.byKey(const Key('failed-turn-retry-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('failed-turn-retry-button')));
    await tester.pump();
    expect(server.startedTurnPrompts, ['网络测试', '网络测试']);
    expect(find.byKey(const Key('failed-turn-retry-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows and cancels the capacity auto-retry countdown', (
    tester,
  ) async {
    final server = FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    expect(await tester.runAsync(() => controller.sendPrompt('容量测试')), isTrue);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'threadId': 'new-thread',
          'turn': {
            'status': 'failed',
            'error': {
              'code': 'model_at_capacity',
              'message': 'Model at capacity',
            },
          },
        },
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('failed-turn-auto-retry-countdown')),
      findsOneWidget,
    );
    expect(find.textContaining('秒后重试'), findsOneWidget);

    await tester.tap(find.byKey(const Key('failed-turn-auto-retry-countdown')));
    await tester.pump();
    expect(
      find.byKey(const Key('failed-turn-auto-retry-countdown')),
      findsNothing,
    );
    expect(find.byKey(const Key('failed-turn-retry-button')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
