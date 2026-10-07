import 'package:chatgpt/src/app.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

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
    expect(find.text('导入（待开发）'), findsOneWidget);
    expect(find.text('语音（待开发）'), findsOneWidget);
    expect(find.text('个性化（待开发）'), findsOneWidget);
    expect(find.text('宠物（待开发）'), findsOneWidget);
    final pendingNavigation = find.byKey(const Key('settings-nav-导入（待开发）'));
    expect(tester.widget<InkWell>(pendingNavigation).onTap, isNull);
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

    await tester.tap(find.byKey(const Key('settings-nav-配置')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('settings-configuration-page')),
      findsOneWidget,
    );

    final backButtonOffset = tester.getTopLeft(
      find.byKey(const Key('settings-back-button')),
    );
    final searchOffset = tester.getTopLeft(
      find.byKey(const Key('settings-search-field')),
    );
    await tester.drag(
      find.byKey(const Key('settings-navigation-scroll')),
      const Offset(0, -220),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const Key('settings-back-button'))),
      backButtonOffset,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('settings-search-field'))),
      searchOffset,
    );
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const Key('settings-navigation-scroll')),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels,
      greaterThan(0),
    );
  });

  testWidgets('appearance settings expose dock icon choices', (tester) async {
    const channel = MethodChannel('codex_desk/dock_icon');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings-nav-外观')));
    await tester.pump();

    expect(find.byKey(const Key('settings-appearance-page')), findsOneWidget);
    expect(find.byKey(const Key('settings-dock-icon-0')), findsOneWidget);
    expect(find.byKey(const Key('settings-dock-icon-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-dock-icon-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings-dock-icon-1')));
    await tester.pump();
    expect(find.text('Dock 图标'), findsOneWidget);
    expect(calls.map((call) => call.method), <String>[
      'getDockIcon',
      'setDockIcon',
      'setDockIcon',
    ]);
    expect(calls[1].arguments, <String, String>{'icon': 'knot'});
    expect(calls[2].arguments, <String, String>{'icon': 'commandCloud'});
  });

  testWidgets('configuration settings expose persisted task defaults', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings-nav-配置')));
    await tester.pump();

    expect(
      find.byKey(const Key('settings-configuration-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-configuration-approval-mode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-configuration-reasoning-effort')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-configuration-diagnose-runtime')),
      findsOneWidget,
    );
    expect(find.text('查看模型与 Provider 状态'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-configuration-effective-approval-policy')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('settings-configuration-approval-mode')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuItem<ApprovalMode>).last);
    await tester.pumpAndSettle();

    expect(controller.approvalMode, ApprovalMode.autoApprove);

    await tester.tap(
      find.byKey(const Key('settings-open-codex-configuration')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('codex-configuration-dialog')), findsOneWidget);
    expect(find.text('打开 config.toml'), findsOneWidget);
    expect(find.byKey(const Key('codex-configured-profile')), findsOneWidget);
  });

  testWidgets('switches the project display mode from the theme menu', (
    tester,
  ) async {
    await tester.pumpWidget(const CodexDeskApp());

    await tester.tap(find.byTooltip('主题：深色 · 午夜'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-mode-light')));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Xedoc'))).brightness,
      Brightness.light,
    );
    final picker = tester.widget<Ink>(
      find.byKey(const Key('workspace-picker-surface')),
    );
    expect((picker.decoration! as BoxDecoration).color, Colors.transparent);
  });

  testWidgets('persists display mode and color preset selections', (
    tester,
  ) async {
    final store = MemoryThemePreferencesStore();
    await tester.pumpWidget(CodexDeskApp(themePreferencesStore: store));

    await tester.tap(find.byTooltip('主题：深色 · 午夜'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-mode-light')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('主题：浅色 · 午夜'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-preset-obsidian')));
    await tester.pumpAndSettle();

    expect(
      store.saved.last,
      const CodexThemePreferences(
        mode: ThemeMode.light,
        preset: YeknomColorPreset.obsidian,
      ),
    );
  });
}
