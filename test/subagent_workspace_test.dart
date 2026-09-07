import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_subagent_avatar.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assigns each subagent a stable supplied avatar', () {
    final reviewAvatar = SubagentAvatar.assetFor('review-thread');

    expect(reviewAvatar, 'assets/subagents/subagent-10.png');
    expect(SubagentAvatar.assetFor('review-thread'), reviewAvatar);
    expect(
      SubagentAvatar.assetFor('implementation-thread'),
      isNot(reviewAvatar),
    );
  });

  testWidgets('shows subagents in a grouped workspace directory', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        id: 'completed-agent-entry',
        kind: TimelineKind.activity,
        title: 'Final integration audit',
        detail: '已完成',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        activityKind: 'collaboration',
        activityStatus: 'completed',
        linkedThreadId: 'final-integration-audit',
        activityPrompt: '审查最终集成。',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const Key('sidebar-agents-button')));
    await tester.pump();

    expect(find.byKey(const Key('agents-page')), findsOneWidget);
    expect(find.text('已开启 · 0'), findsOneWidget);
    expect(find.text('完成 · 1'), findsOneWidget);
    expect(find.text('Final integration audit'), findsOneWidget);
    expect(find.text('2 小时前'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows every concurrently running subagent in the inspector', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running
      ..activeThreadId = 'parent-thread'
      ..activeTurnId = 'parent-turn';
    for (final item in const [
      {
        'id': 'spawn-review',
        'type': 'subAgentActivity',
        'kind': 'started',
        'agentThreadId': 'review-thread',
        'agentPath': '/root/review_app',
      },
      {
        'id': 'spawn-tests',
        'type': 'subAgentActivity',
        'kind': 'started',
        'agentThreadId': 'test-thread',
        'agentPath': '/root/review_tests',
      },
    ]) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/started',
          params: {
            'threadId': 'parent-thread',
            'turnId': 'parent-turn',
            'item': item,
          },
        ),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('live-collaboration-activities-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('live-subagent-activity-open-spawn-review')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('live-subagent-activity-open-spawn-tests')),
      findsOneWidget,
    );
    expect(find.text('2 个运行中'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sidebar-agents-button')));
    await tester.pump();
    expect(find.text('已开启 · 2'), findsOneWidget);
    expect(find.text('review_app'), findsOneWidget);
    expect(find.text('review_tests'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens subagent tabs from the inspector summary', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        id: 'inspector-agent-entry',
        kind: TimelineKind.activity,
        title: 'Login entry integration',
        detail: '已完成',
        createdAt: DateTime.now(),
        activityKind: 'collaboration',
        activityStatus: 'completed',
        linkedThreadId: 'login-entry-integration',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );
    expect(
      find.byKey(const Key('inspector-subagents-open-all')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('inspector-subagents-open-all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agents-page')), findsNothing);
    expect(
      find.byKey(const ValueKey('full-height-side-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('side-panel-tab-subagent:login-entry-integration'),
      ),
      findsOneWidget,
    );
    expect(find.text('Login entry integration'), findsNWidgets(3));
    final workbenchTopBar = tester.getRect(
      find.byKey(const Key('workbench-column-topbar')),
    );
    final panelToggle = tester.getRect(
      find.byKey(const Key('side-panel-collapse')),
    );
    expect(panelToggle.size, const Size.square(40));
    expect(1280 - panelToggle.right, closeTo(16, 0.1));
    expect(workbenchTopBar.right, lessThanOrEqualTo(panelToggle.left));
    expect(
      find.byKey(
        const ValueKey('side-panel-tab-close-subagent:login-entry-integration'),
      ),
      findsNothing,
    );

    await tester.binding.setSurfaceSize(const Size(2048, 900));
    await tester.pumpAndSettle();
    final fullHeightPanel = tester.getRect(
      find.byKey(const Key('full-height-side-panel')),
    );
    expect(fullHeightPanel.top, 0);
    expect(fullHeightPanel.bottom, 900);
    expect(find.byKey(const Key('codex-environment-card')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const Key('conversation-viewport-stack')))
          .width,
      greaterThanOrEqualTo(720),
    );
    final expandedConversation = tester.getRect(
      find.byKey(const Key('conversation-viewport-stack')),
    );
    expect(expandedConversation.right, lessThanOrEqualTo(fullHeightPanel.left));
    expect(
      2048 - tester.getRect(find.byKey(const Key('side-panel-collapse'))).right,
      closeTo(16, 0.1),
    );

    await tester.tap(find.byKey(const Key('side-panel-collapse')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('code-review-panel')), findsNothing);
    expect(find.byKey(const Key('side-panel-expand')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('side-panel-expand'))),
      const Size.square(40),
    );

    await tester.tap(find.byKey(const Key('side-panel-expand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('subagent-thread-panel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('side-panel-collapse')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('workbench-file-changes-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('side-panel-tab-review')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('side-panel-tab-subagent:login-entry-integration'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('code-review-panel')), findsOneWidget);
    expect(find.byKey(const Key('code-review-close')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
