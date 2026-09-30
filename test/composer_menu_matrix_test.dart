import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

List<String> _commandKinds(WidgetTester tester, Finder menu) => find
    .descendant(of: menu, matching: find.byType(InkWell))
    .evaluate()
    .map((element) => element.widget.key)
    .whereType<ValueKey<String>>()
    .map((key) => key.value)
    .where((value) => value.startsWith('composer-slash-command-'))
    .map((value) => value.substring('composer-slash-command-'.length))
    .toList(growable: false);

bool _commandEnabled(WidgetTester tester, String kind) =>
    tester
        .widget<InkWell>(find.byKey(ValueKey('composer-slash-command-$kind')))
        .onTap !=
    null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keeps the new-chat slash mention and add matrices stable', (
    tester,
  ) async {
    final controller = CodexController(server: FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/');
    await tester.pump();

    final slashMenu = find.byKey(const Key('composer-slash-menu'));
    expect(slashMenu, findsOneWidget);
    expect(_commandKinds(tester, slashMenu), [
      'workspaceContext',
      'mcpStatus',
      'codeReview',
      'goal',
      'planMode',
      'sideChat',
      'forkChat',
      'compact',
      'feedback',
      'archive',
      'reasoning',
      'newChat',
      'model',
    ]);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(
              const ValueKey('composer-slash-command-workspaceContext'),
            ),
          )
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('composer-slash-command-sideChat')),
          )
          .onTap,
      isNull,
    );

    await tester.enterText(field, '@');
    await tester.pump();

    final mentionMenu = find.byKey(const Key('composer-mention-menu'));
    expect(mentionMenu, findsOneWidget);
    expect(_commandKinds(tester, mentionMenu), [
      'files',
      'workspaceContext',
      'goal',
      'planMode',
      'recordSkill',
    ]);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('composer-slash-command-recordSkill')),
          )
          .onTap,
      isNull,
    );

    await tester.enterText(field, '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();

    final addItems = find
        .byWidgetPredicate((widget) => widget is PopupMenuItem<AddMenuAction>)
        .evaluate()
        .map((element) => element.widget.key)
        .whereType<Key>()
        .where(
          (key) =>
              key == const Key('add-files-menu-item') ||
              key == const Key('add-workspace-menu-item') ||
              key == const Key('add-goal-menu-item') ||
              key == const Key('add-plan-mode-menu-item') ||
              key == const Key('record-skill-menu-item'),
        )
        .toList(growable: false);
    expect(addItems, [
      const Key('add-files-menu-item'),
      const Key('add-workspace-menu-item'),
      const Key('add-goal-menu-item'),
      const Key('add-plan-mode-menu-item'),
      const Key('record-skill-menu-item'),
    ]);
    expect(find.byKey(const Key('draw-menu-item')), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuItem<AddMenuAction>>(
            find.byKey(const Key('draw-menu-item')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<PopupMenuItem<AddMenuAction>>(
            find.byKey(const Key('record-skill-menu-item')),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets(
    'keeps command availability stable from new chat through running and completion',
    (tester) async {
      final server = FakeCodexAppServer();
      final controller = CodexController(server: server)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final field = find.byKey(const Key('composer-field'));
      await tester.enterText(field, '/');
      await tester.pump();
      expect(_commandEnabled(tester, 'codeReview'), isTrue);
      expect(_commandEnabled(tester, 'forkChat'), isFalse);
      expect(_commandEnabled(tester, 'compact'), isFalse);
      expect(_commandEnabled(tester, 'archive'), isFalse);
      expect(_commandEnabled(tester, 'newChat'), isTrue);

      await tester.enterText(field, '');
      expect(await controller.sendPrompt('run state'), isTrue);
      controller.threads = const [
        CodexThread(
          id: 'new-thread',
          preview: 'run state',
          createdAt: 1,
          updatedAt: 1,
        ),
      ];
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'new-thread',
            'turn': {'id': 'running-turn'},
          },
        ),
      );
      await tester.pump();
      await tester.enterText(field, '/');
      await tester.pump();
      expect(_commandEnabled(tester, 'codeReview'), isFalse);
      expect(_commandEnabled(tester, 'planMode'), isFalse);
      expect(_commandEnabled(tester, 'forkChat'), isTrue);
      expect(_commandEnabled(tester, 'compact'), isFalse);
      expect(_commandEnabled(tester, 'archive'), isFalse);
      expect(_commandEnabled(tester, 'newChat'), isTrue);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/completed',
          params: {
            'threadId': 'new-thread',
            'turn': {'id': 'running-turn', 'status': 'completed'},
          },
        ),
      );
      await tester.pump();
      await tester.enterText(field, '/');
      await tester.pump();
      expect(_commandEnabled(tester, 'codeReview'), isTrue);
      expect(_commandEnabled(tester, 'planMode'), isTrue);
      expect(_commandEnabled(tester, 'forkChat'), isTrue);
      expect(_commandEnabled(tester, 'compact'), isTrue);
      expect(_commandEnabled(tester, 'archive'), isTrue);

      await tester.tap(
        find.byKey(const ValueKey('composer-slash-command-codeReview')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer-slash-menu')), findsNothing);
      expect(
        find.byKey(const Key('composer-code-review-options-panel')),
        findsOneWidget,
      );
    },
  );

  testWidgets('keeps command menus closed while the runtime is offline', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.stopped;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, '/');
    await tester.pump();
    expect(find.byKey(const Key('composer-slash-menu')), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    await tester.enterText(field, '@');
    await tester.pump();
    expect(find.byKey(const Key('composer-mention-menu')), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
  });
}
