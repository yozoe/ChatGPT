import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
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
    expect(
      tester
          .widget<PopupMenuItem<AddMenuAction>>(
            find.byKey(const Key('record-skill-menu-item')),
          )
          .enabled,
      isFalse,
    );
  });
}
