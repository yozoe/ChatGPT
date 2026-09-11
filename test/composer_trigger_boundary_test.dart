import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('does not open mention or slash menus for invalid ranges', (
    tester,
  ) async {
    final controller =
        CodexController(server: CodexAppServer(executable: '/not/a/codex'))
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    final composer = TextEditingController();
    addTearDown(() {
      composer.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposerPanel(
            controller: controller,
            composer: composer,
            onSend: (_) async => true,
            onQueueSteer: (_) async => true,
          ),
        ),
      ),
    );
    final field = find.byKey(const Key('composer-field'));

    for (final value in [
      '先说明 @main',
      '先说明 /model',
      '@main 文件',
      '/model 参数',
      '@main\n下一行',
      '/model\n下一行',
    ]) {
      await tester.enterText(field, value);
      await tester.pump();
      expect(find.byKey(const Key('composer-mention-menu')), findsNothing);
      expect(find.byKey(const Key('composer-slash-menu')), findsNothing);
    }

    await tester.enterText(field, '@');
    await tester.pump();
    expect(find.byKey(const Key('composer-mention-menu')), findsOneWidget);
    await tester.enterText(field, '/');
    await tester.pump();
    expect(find.byKey(const Key('composer-slash-menu')), findsOneWidget);
  });
}
