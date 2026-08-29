import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sidebar settings and help entries open their surfaces', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();

    final mainSidebarWidth = tester
        .getSize(find.byKey(const Key('sidebar-pane')))
        .width;
    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pump();
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
    expect(find.byKey(const Key('settings-general-page')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-pane')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('settings-navigation-pane'))).width,
      mainSidebarWidth,
    );

    await tester.tap(find.byKey(const Key('settings-back-button')));
    await tester.pump();
    expect(find.byKey(const Key('sidebar-pane')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sidebar-help-button')));
    await tester.pump();
    expect(find.byKey(const Key('help-keyboard-shortcuts')), findsOneWidget);
    expect(find.byKey(const Key('help-open-help')), findsOneWidget);
  });

  testWidgets('settings navigation remains usable in a narrow window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(680, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('sidebar-resize-handle')),
      const Offset(100, 0),
    );
    await tester.pump();
    final mainSidebarWidth = tester
        .getSize(find.byKey(const Key('sidebar-pane')))
        .width;
    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('settings-general-page')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('settings-navigation-pane'))).width,
      mainSidebarWidth,
    );
  });
}
