import 'dart:io';
import 'widget_test_fakes.dart';

import 'package:chatgpt/src/app.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_top_bar.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_status_pill.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

typedef _FakeRuntimeConfigurationStore = FakeRuntimeConfigurationStore;
typedef _MemoryConversationHistoryStore = MemoryConversationHistoryStore;
typedef _MemoryCodexPluginStore = MemoryCodexPluginStore;
typedef _FakeCodexAppServer = FakeCodexAppServer;
typedef _WorkspaceSwitchingController = WorkspaceSwitchingController;

/// 创建具有可预测字段的测试线程。
/// Creates a test thread with predictable fields.
CodexThread _thread({
  required String id,
  String? modelProvider,
  String? model,
  String? status,
}) => CodexThread(
  id: id,
  preview: 'preview-$id',
  createdAt: 1,
  updatedAt: 2,
  modelProvider: modelProvider,
  model: model,
  status: status,
);

void main() {
  late _MemoryConversationHistoryStore historyStore;
  late _FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    historyStore = _MemoryConversationHistoryStore();
    runtimeConfigurationStore = _FakeRuntimeConfigurationStore();
    CodexController.testingConversationHistoryStore = historyStore;
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  testWidgets('shows the Xedoc shell', (tester) async {
    await tester.pumpWidget(const CodexDeskApp());

    expect(find.text('Xedoc'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    final brandText = tester.widget<Text>(find.text('Xedoc'));
    expect(brandText.style?.fontSize, 17);
    expect(brandText.style?.fontWeight, FontWeight.w700);
    expect(find.text('新建第一个工作区'), findsOneWidget);
    expect(find.text('从一个工作区开始'), findsOneWidget);
    expect(
      find.byKey(const Key('sidebar-first-workspace-create-button')),
      findsOneWidget,
    );
    expect(find.text('等待目录'), findsOneWidget);
    expect(find.byKey(const Key('runtime-start-button')), findsNothing);
    expect(find.byTooltip('停止运行时'), findsNothing);
    expect(find.text('新建任务'), findsOneWidget);
    expect(find.byKey(const Key('sidebar-new-chat-button')), findsOneWidget);
    expect(
      find.byKey(const Key('sidebar-pull-requests-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('sidebar-scheduled-tasks-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sidebar-plugins-button')), findsOneWidget);
    expect(tester.widget<Text>(find.text('新对话')).style?.fontSize, 12);
    final pluginMenuAction = find.byKey(const Key('sidebar-plugins-button'));
    final pluginMenuMark = find.descendant(
      of: pluginMenuAction,
      matching: find.byType(SvgPicture),
    );
    expect(pluginMenuMark, findsOneWidget);
    expect(tester.getSize(pluginMenuAction).height, 32);
    expect(
      (tester.getCenter(pluginMenuMark).dy -
              tester.getCenter(find.text('插件')).dy)
          .abs(),
      lessThan(.5),
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('sidebar-new-chat-button')),
              matching: find.byIcon(Icons.edit_outlined),
            ),
          )
          .size,
      16,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('task-search-button')),
              matching: find.byIcon(Icons.search),
            ),
          )
          .size,
      17,
    );
  });

  testWidgets('opens the three project-library workspaces from the sidebar', (
    tester,
  ) async {
    final controller =
        CodexController(
            server: CodexAppServer(),
            pluginStore: _MemoryCodexPluginStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready
          ..threads = [_thread(id: 'thread-1', status: 'idle')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('sidebar-scheduled-tasks-button')));
    await tester.pump();
    expect(find.byKey(const Key('scheduled-tasks-page')), findsOneWidget);
    expect(find.text('已安排的任务'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('sidebar-thread-tile-thread-1')),
    );
    await tester.pump();
    expect(find.byKey(const Key('scheduled-tasks-page')), findsNothing);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
    await tester.pump();
    expect(find.byKey(const Key('plugins-page')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('sidebar-thread-tile-thread-1')),
    );
    await tester.pump();
    expect(find.byKey(const Key('plugins-page')), findsNothing);

    await tester.tap(find.byKey(const Key('sidebar-pull-requests-button')));
    await tester.pump();
    expect(find.text('Pull Request'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('sidebar-thread-tile-thread-1')),
    );
    await tester.pump();
    expect(find.text('Pull Request'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new-task entry points always return to the conversation', (
    tester,
  ) async {
    final controller =
        CodexController(
            server: CodexAppServer(),
            pluginStore: _MemoryCodexPluginStore(),
          )
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready
          ..activeThreadId = 'thread-1';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    Future<void> openPlugins() async {
      await tester.tap(find.byKey(const Key('sidebar-plugins-button')));
      await tester.pump();
      expect(find.byKey(const Key('plugins-page')), findsOneWidget);
    }

    void expectConversation() {
      expect(find.byKey(const Key('plugins-page')), findsNothing);
      expect(find.byKey(const Key('composer-field')), findsOneWidget);
      expect(controller.activeThreadId, isNull);
    }

    await openPlugins();
    await tester.tap(find.byKey(const Key('sidebar-new-chat-button')));
    await tester.pump();
    expectConversation();

    controller.activeThreadId = 'thread-2';
    await openPlugins();
    await tester.tap(find.byKey(const Key('task-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新聊天'));
    await tester.pumpAndSettle();
    expectConversation();

    controller.activeThreadId = 'thread-3';
    await openPlugins();
    final workspaceTile = find.byKey(
      const ValueKey('sidebar-workspace-/workspace'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(workspaceTile));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sidebar-workspace-edit-/workspace')),
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expectConversation();

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('starts a new task in the project whose row action was used', (
    tester,
  ) async {
    late Directory root;
    late String firstPath;
    late String secondPath;
    late CodexController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'codex-desk-new-task-project-',
      );
      final first = await Directory('${root.path}/first').create();
      final second = await Directory('${root.path}/second').create();
      firstPath = await first.resolveSymbolicLinks();
      secondPath = await second.resolveSymbolicLinks();
      final runtimeStore = _FakeRuntimeConfigurationStore()
        ..workspace = secondPath
        ..workspaces = [
          WorkspaceConfiguration(id: 'first-project', primaryPath: firstPath),
          WorkspaceConfiguration(id: 'second-project', primaryPath: secondPath),
        ];
      controller = _WorkspaceSwitchingController(store: runtimeStore);
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.ready;
    });
    addTearDown(() => root.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final firstTile = find.byKey(ValueKey('sidebar-workspace-$firstPath'));
    await tester.ensureVisible(firstTile);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(firstTile));
    await tester.pump();
    final newTaskButton = find.byKey(
      ValueKey('sidebar-workspace-edit-$firstPath'),
    );
    expect(newTaskButton, findsOneWidget);
    expect(tester.widget<IconButton>(newTaskButton).onPressed, isNotNull);

    tester.widget<IconButton>(newTaskButton).onPressed!();
    await tester.pump();

    expect(controller.workspacePath, firstPath);
    expect(controller.activeThreadId, isNull);
    expect(
      controller.entries.map((entry) => entry.title),
      isNot(contains('已新建任务')),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gives the project and workbench columns independent top bars', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final projectTopBar = find.byKey(const Key('workspace-column-topbar'));
    final workbenchTopBar = find.byKey(const Key('workbench-column-topbar'));
    final sidebar = find.byKey(const Key('sidebar-pane'));

    expect(projectTopBar, findsOneWidget);
    expect(workbenchTopBar, findsOneWidget);
    expect(tester.getTopLeft(projectTopBar).dx, lessThan(250));
    expect(
      tester.getTopLeft(workbenchTopBar).dx,
      greaterThan(tester.getTopLeft(projectTopBar).dx),
    );
    expect(
      tester.getTopLeft(sidebar).dy,
      greaterThan(tester.getBottomLeft(projectTopBar).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('workbench-task-title'))).dy,
      lessThan(tester.getBottomLeft(workbenchTopBar).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('composer-panel'))).dy,
      greaterThan(tester.getBottomLeft(workbenchTopBar).dy),
    );
    final environmentPane = find.byKey(const Key('environment-inspector-pane'));
    expect(
      tester.getTopLeft(environmentPane).dy,
      closeTo(tester.getBottomLeft(workbenchTopBar).dy, 1.1),
    );
    expect(
      tester.getTopRight(workbenchTopBar).dx,
      lessThanOrEqualTo(tester.getTopLeft(environmentPane).dx),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('positions project identity below the macOS window controls', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 332,
            child: TopBar(
              controller: controller,
              themeMode: ThemeMode.dark,
              themePreset: YeknomColorPreset.workbench,
              onThemeModeChanged: null,
              onThemePresetChanged: null,
              onChooseWorkspace: () {},
              onAccount: () async {},
              onCodexConfiguration: () async {},
              onPlugins: () async {},
              showIdentity: true,
              showControls: false,
            ),
          ),
        ),
      ),
    );

    final identityRect = tester.getRect(find.text('Xedoc'));
    final statusRect = tester.getRect(find.byType(StatusPill));
    expect(identityRect.left, greaterThanOrEqualTo(72));
    expect(identityRect.top, greaterThanOrEqualTo(16));
    expect(statusRect.right, 324);
    expect(statusRect.center.dy, closeTo(identityRect.center.dy, 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps settings content on the transparent title-bar surface', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(900, 700),
            padding: EdgeInsets.only(top: 24),
          ),
          child: CodexWorkspace(controller: controller),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('sidebar-settings-button')));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(const Key('settings-page'))).dy, 0);
    expect(
      tester.getTopLeft(find.byKey(const Key('settings-back-button'))).dy,
      22,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('left aligns the workbench top bar with its column', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1980, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final topBar = find.byKey(const Key('workbench-column-topbar'));
    final resizeHandle = find.byKey(const Key('sidebar-resize-handle'));
    expect(
      tester.getTopLeft(topBar).dx,
      closeTo(tester.getTopRight(resizeHandle).dx, 0.1),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('centers the wider timeline and composer on one rail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();

    final viewport = find.byKey(const Key('conversation-viewport-stack'));
    final timeline = find.descendant(
      of: viewport,
      matching: find.byType(ListView),
    );
    final composerSurface = find.byKey(const Key('composer-surface-stack'));
    final timelineWidget = tester.widget<ListView>(timeline);
    final timelinePadding = timelineWidget.padding! as EdgeInsets;

    expect(timelinePadding.left, conversationContentHorizontalInset);
    expect(timelinePadding.right, conversationContentHorizontalInset);
    expect(
      tester.getCenter(composerSurface).dx,
      closeTo(tester.getCenter(timeline).dx, 0.1),
    );
    expect(
      tester.getSize(composerSurface).width,
      closeTo(
        tester.getSize(timeline).width -
            (conversationContentHorizontalInset * 2),
        0.1,
      ),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the message rail visible at the conversation edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        id: 'wide-workspace-user-message',
        kind: TimelineKind.user,
        title: 'You',
        detail: '宽窗口中的用户消息',
        createdAt: DateTime(2026),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();

    for (final size in const [Size(1280, 900), Size(1980, 900)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();

      final viewport = find.byKey(const Key('conversation-viewport-stack'));
      final rail = find.byKey(const Key('conversation-user-message-rail'));
      final timeline = find.descendant(
        of: viewport,
        matching: find.byType(ListView),
      );
      final viewportRect = tester.getRect(viewport);
      final railRect = tester.getRect(rail);

      expect(tester.getSize(timeline).width, closeTo(790, 0.1));
      expect(railRect.left, closeTo(viewportRect.left + 16, 0.1));
      expect(railRect.right, lessThan(viewportRect.right));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps conversation errors on the centered content rail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1980, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer());
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    controller.workspacePath = '/workspace';
    controller.createThread();
    expect(controller.lastError, isNotNull);
    await tester.pump();

    final viewport = find.byKey(const Key('conversation-viewport-stack'));
    final banner = find.byKey(const Key('conversation-error-banner'));
    final timeline = find.descendant(
      of: viewport,
      matching: find.byType(ListView),
    );

    expect(banner, findsOneWidget);
    expect(tester.getSize(viewport).width, greaterThan(790));
    expect(tester.getSize(banner).width, closeTo(790, 0.1));
    expect(
      tester.getCenter(banner).dx,
      closeTo(tester.getCenter(timeline).dx, 0.1),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hides file stats when a Diff has no countable lines', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'assets/logo.png',
                'kind': 'modified',
                'diff': 'diff --git a/assets/logo.png b/assets/logo.png',
              },
            ],
          },
        },
      ),
    );
    await tester.pump();

    final pill = find.byKey(const Key('composer-file-change-pill'));
    expect(find.descendant(of: pill, matching: find.text('+?')), findsNothing);
    expect(find.descendant(of: pill, matching: find.text('-?')), findsNothing);
    expect(find.descendant(of: pill, matching: find.text('+0')), findsNothing);
    expect(find.descendant(of: pill, matching: find.text('-0')), findsNothing);
    expect(find.byKey(const Key('file-change-summary-stats')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps live file stats while another Diff is pending', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.running;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'lib/ready.dart',
                'kind': 'modified',
                'diff': '@@ -1 +1,2 @@\n-old\n+new\n+another',
              },
              {'path': 'lib/pending.dart', 'kind': 'modified'},
            ],
          },
        },
      ),
    );
    await tester.pump();

    final pill = find.byKey(const Key('composer-file-change-pill'));
    expect(
      find.descendant(of: pill, matching: find.text('+2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pill, matching: find.text('-1')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('edits the current task name from the workbench top bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'active-task'
      ..threads = [
        const CodexThread(
          id: 'active-task',
          name: '初始任务名称',
          preview: '任务预览',
          createdAt: 1,
          updatedAt: 1,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final topBar = find.byKey(const Key('workbench-column-topbar'));
    expect(
      find.descendant(of: topBar, matching: find.text('初始任务名称')),
      findsOneWidget,
    );
    expect(find.text('任务控制台'), findsNothing);

    await tester.tap(find.byKey(const Key('workbench-task-title')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('workbench-task-title-editor')),
      '整理桌面工作台布局',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(server.renamedThreadId, 'active-task');
    expect(server.renamedThreadName, '整理桌面工作台布局');
    expect(
      find.descendant(of: topBar, matching: find.text('整理桌面工作台布局')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lazily builds a long sidebar conversation list', (tester) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = List.generate(
        240,
        (index) => _thread(id: 'lazy-thread-$index'),
      );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final taskList = find.byKey(const Key('sidebar-task-list'));
    expect(taskList, findsOneWidget);
    expect(find.text('preview-lazy-thread-0'), findsOneWidget);
    expect(find.text('preview-lazy-thread-239'), findsNothing);
    final listView = tester.widget<ListView>(taskList);
    expect(listView.itemExtentBuilder, isNotNull);
    final scrollController = listView.controller!;
    scrollController.jumpTo(420);
    await tester.pump();
    final readingOffset = scrollController.offset;
    controller.notifyListeners();
    await tester.pump();
    expect(scrollController.offset, closeTo(readingOffset, 0.1));

    await tester.dragUntilVisible(
      find.text('preview-lazy-thread-239'),
      taskList,
      const Offset(0, -420),
    );
    expect(find.text('preview-lazy-thread-239'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
