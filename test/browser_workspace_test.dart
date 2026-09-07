import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_conversation_pane.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_fakes/fake_runtime_configuration_store.dart';
import 'widget_fakes/memory_codex_plugin_store.dart';
import 'widget_fakes/memory_conversation_history_store.dart';

/// Creates a browser-workspace test thread with predictable fields.
CodexThread createBrowserWorkspaceTestThread({required String id}) =>
    CodexThread(
      id: id,
      preview: 'preview-$id',
      createdAt: 1,
      updatedAt: 2,
      status: 'idle',
    );

void main() {
  setUp(() {
    CodexController.testingConversationHistoryStore =
        MemoryConversationHistoryStore();
    CodexController.testingRuntimeConfigurationStore =
        FakeRuntimeConfigurationStore();
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  testWidgets('defers native browser creation until its workspace tab opens', (
    tester,
  ) async {
    final controller = CodexController(
      server: CodexAppServer(messageSink: (_) {}),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );
    expect(find.byKey(const Key('browser-workspace-page')), findsNothing);
    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-nav-浏览器')),
      240,
      scrollable: find.descendant(
        of: find.byKey(const Key('settings-navigation-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('settings-nav-浏览器')));
    await tester.pump();
    expect(find.byKey(const Key('browser-workspace-page')), findsNothing);
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'browser/open',
        requestId: 'browser-test-1',
        params: {'url': 'https://example.com'},
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('browser-workspace-page')), findsNothing);
    await controller.respondToApproval(accepted: true);
    await tester.pump();
    expect(find.byKey(const Key('browser-workspace-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('side-panel-tab-browser')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('workbench-column-topbar')), findsOneWidget);
    expect(find.byType(ConversationPane), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual browser launcher opens a retained workspace tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(
      server: CodexAppServer(messageSink: (_) {}),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );
    expect(find.byKey(const Key('browser-workspace-page')), findsNothing);
    expect(find.byKey(const Key('environment-inspector-pane')), findsOneWidget);
    await tester.tap(find.byTooltip('展开右侧工作区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览器'));
    await tester.pump();
    expect(find.byKey(const Key('browser-workspace-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('side-panel-tab-browser')),
      findsOneWidget,
    );
    expect(find.byType(ConversationPane), findsOneWidget);
    expect(find.byKey(const Key('environment-inspector-pane')), findsNothing);
    expect(find.text('开始浏览'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('browser-address')),
      'retained.example',
    );
    await tester.tap(find.byTooltip('收起右侧工作区'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('browser-workspace-page')), findsNothing);
    expect(
      find.byKey(const Key('browser-workspace-page'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const Key('browser-address')), findsNothing);
    expect(find.byKey(const Key('environment-inspector-pane')), findsOneWidget);
    final hiddenBrowser = find.byKey(
      const Key('browser-workspace-page'),
      skipOffstage: false,
    );
    final hiddenAddressField = find.descendant(
      of: hiddenBrowser,
      matching: find.byType(EditableText, skipOffstage: false),
    );
    expect(
      tester.widget<EditableText>(hiddenAddressField).focusNode.hasFocus,
      isFalse,
    );
    await tester.tap(find.byTooltip('展开右侧工作区'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      'retained.example',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual files launcher opens a retained workspace tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(
      server: CodexAppServer(messageSink: (_) {}),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );
    await tester.tap(find.byTooltip('展开右侧工作区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件'));
    await tester.pump();
    expect(find.byKey(const ValueKey('files-workspace-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('side-panel-tab-files')), findsOneWidget);
    expect(find.text('尚未打开工作区'), findsOneWidget);
    expect(find.byType(ConversationPane), findsOneWidget);
    expect(find.byKey(const Key('environment-inspector-pane')), findsNothing);
    await tester.tap(find.byTooltip('收起右侧工作区'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('files-workspace-page')), findsNothing);
    expect(
      find.byKey(const ValueKey('files-workspace-page'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps browser state across full-page destinations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller =
        CodexController(
            server: CodexAppServer(messageSink: (_) {}),
            pluginStore: MemoryCodexPluginStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready
          ..threads = [createBrowserWorkspaceTestThread(id: 'thread-1')];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: CodexWorkspace(controller: controller)),
      ),
    );
    await tester.tap(find.byTooltip('展开右侧工作区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览器'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('browser-address')),
      'retained-across-destinations.example',
    );
    for (final navigationKey in const [
      Key('sidebar-scheduled-tasks-button'),
      Key('sidebar-plugins-button'),
      Key('sidebar-agents-button'),
      Key('sidebar-pull-requests-button'),
    ]) {
      await tester.tap(find.byKey(navigationKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browser-workspace-page')), findsNothing);
      expect(
        find.byKey(const Key('browser-workspace-page'), skipOffstage: false),
        findsOneWidget,
        reason: 'browser should remain mounted after opening $navigationKey',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('browser-address'), skipOffstage: false),
            )
            .controller
            ?.text,
        'retained-across-destinations.example',
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('browser-workspace-page')), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('browser-address'), skipOffstage: false),
          )
          .controller
          ?.text,
      'retained-across-destinations.example',
    );
    await tester.tap(find.byKey(const Key('settings-back-button')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sidebar-thread-tile-thread-1')),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      'retained-across-destinations.example',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
