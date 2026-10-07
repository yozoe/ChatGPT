import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/codex_hover_popup.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_workspace_tile.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'widget_test_fakes.dart';

CodexThread threadForTest({
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryConversationHistoryStore historyStore;
  late FakeRuntimeConfigurationStore runtimeConfigurationStore;

  setUp(() {
    historyStore = MemoryConversationHistoryStore();
    runtimeConfigurationStore = FakeRuntimeConfigurationStore();
    CodexController.testingConversationHistoryStore = historyStore;
    CodexController.testingRuntimeConfigurationStore =
        runtimeConfigurationStore;
  });

  tearDown(() {
    CodexController.testingConversationHistoryStore = null;
    CodexController.testingRuntimeConfigurationStore = null;
  });

  testWidgets('shows saved workspaces as a switchable sidebar list', (
    tester,
  ) async {
    late Directory root;
    late String firstPath;
    late String secondPath;
    late CodexController controller;
    late FakeRuntimeConfigurationStore runtimeStore;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'codex-desk-sidebar-workspaces-',
      );
      final first = await Directory(
        '${root.path}/first-project',
      ).create(recursive: true);
      final second = await Directory(
        '${root.path}/second-project',
      ).create(recursive: true);
      final additional = await Directory(
        '${root.path}/shared',
      ).create(recursive: true);
      firstPath = await first.resolveSymbolicLinks();
      secondPath = await second.resolveSymbolicLinks();
      runtimeStore = FakeRuntimeConfigurationStore()
        ..workspace = second.path
        ..workspaces = [
          WorkspaceConfiguration(
            primaryPath: first.path,
            additionalPaths: [additional.path],
          ),
          WorkspaceConfiguration(primaryPath: second.path),
        ];
      controller = CodexController(
        server: ManagedRuntimeFakeServer(),
        runtimeConfigurationStore: runtimeStore,
      );
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.ready;
      controller.threads = [
        threadForTest(id: 'nested-task', status: 'idle'),
        threadForTest(id: 'delayed-completion-task'),
        threadForTest(id: 'failed-task', status: 'systemError'),
      ];
      historyStore.snapshots[firstPath] = ConversationHistorySnapshot(
        // 缓存中可能保留了已在其他项目恢复的同一线程 ID；它不能继承
        // 当前项目的选中态或运行中状态。
        threads: [
          const CodexThread(
            id: 'nested-task',
            preview: 'preview-cached-first-task',
            createdAt: 1,
            updatedAt: 2,
          ),
        ],
        archivedThreads: const [],
        entries: const [],
        fileChanges: const [],
      );
      await controller.refreshInactiveWorkspaceTaskLists();
    });
    addTearDown(() => root.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final firstTile = find.byKey(ValueKey('sidebar-workspace-$firstPath'));
    final secondTile = find.byKey(ValueKey('sidebar-workspace-$secondPath'));
    expect(firstTile, findsOneWidget);
    expect(secondTile, findsOneWidget);
    expect(find.text('first-project'), findsOneWidget);
    expect(find.text('second-project'), findsOneWidget);
    expect(find.text(firstPath), findsNothing);
    expect(find.byTooltip(firstPath), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    final nestedTask = find.text('preview-nested-task', skipOffstage: false);
    expect(nestedTask, findsOneWidget);
    await tester.ensureVisible(nestedTask);
    await tester.pump();
    expect(
      find.byKey(const Key('sidebar-completed-task-indicator')),
      findsOneWidget,
    );
    await tester.ensureVisible(nestedTask);
    await tester.pump();
    await tester.tap(nestedTask);
    await tester.pump();
    expect(
      find.byKey(const Key('sidebar-completed-task-indicator')),
      findsNothing,
    );
    // The completion status can arrive after a task has already been opened.
    // That delayed refresh must not revive an old completion reminder.
    final delayedTask = find.text('preview-delayed-completion-task');
    await tester.ensureVisible(delayedTask);
    await tester.pump();
    await tester.tap(delayedTask);
    await tester.pump();
    controller.threads = [
      threadForTest(id: 'nested-task', status: 'idle'),
      threadForTest(id: 'delayed-completion-task', status: 'idle'),
      threadForTest(id: 'failed-task', status: 'systemError'),
    ];
    controller.notifyListeners();
    await tester.pump();
    expect(
      find.byKey(const Key('sidebar-completed-task-indicator')),
      findsNothing,
    );
    await tester.fling(
      find.byKey(const Key('sidebar-task-list')),
      const Offset(0, 800),
      2000,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(firstTile).dy,
      lessThan(tester.getTopLeft(secondTile).dy),
    );
    final activePathBeforeToggle = controller.workspacePath;
    final firstTileSurface = find.descendant(
      of: firstTile,
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(firstTile);
    await tester.tap(firstTileSurface.first);
    await tester.pump(const Duration(milliseconds: 220));
    expect(controller.workspacePath, activePathBeforeToggle);
    await tester.tap(firstTileSurface.first);
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('preview-cached-first-task'), findsOneWidget);
    await tester.ensureVisible(firstTile);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await tester.ensureVisible(firstTile);
    await mouse.moveTo(tester.getCenter(firstTile));
    await tester.pump();
    final moreButton = find.byKey(
      ValueKey('sidebar-workspace-more-$firstPath'),
    );
    final newTaskButton = find.byKey(
      ValueKey('sidebar-workspace-edit-$firstPath'),
    );
    expect(moreButton, findsOneWidget);
    expect(newTaskButton, findsOneWidget);
    // 项目详情卡片只会在持续悬停后显示。
    expect(find.text('1 个任务'), findsNothing);
    expect(find.text('编辑项目'), findsNothing);
    await tester.pump(codexHoverPopupDelay - const Duration(milliseconds: 1));
    expect(find.text('1 个任务'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('1 个任务'), findsOneWidget);
    expect(find.text('编辑项目'), findsOneWidget);
    expect(tester.widget<Text>(find.text('1 个任务')).style?.fontSize, 12);
    expect(tester.widget<Text>(find.text('编辑项目')).style?.fontSize, 12);
    // A project can receive new tasks after its count was first shown. Opening
    // its details again must reload the local cache instead of retaining 1.
    await tester.ensureVisible(secondTile);
    await mouse.moveTo(tester.getCenter(secondTile));
    await tester.pump(const Duration(milliseconds: 180));
    historyStore.snapshots[firstPath] = ConversationHistorySnapshot(
      threads: [
        const CodexThread(
          id: 'nested-task',
          preview: 'preview-cached-first-task',
          createdAt: 1,
          updatedAt: 2,
        ),
        const CodexThread(
          id: 'new-cached-first-task',
          preview: 'preview-new-cached-first-task',
          createdAt: 3,
          updatedAt: 4,
        ),
      ],
      archivedThreads: const [],
      entries: const [],
      fileChanges: const [],
    );
    await tester.fling(
      find.byKey(const Key('sidebar-task-list')),
      const Offset(0, 800),
      2000,
    );
    await tester.pumpAndSettle();
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(firstTile));
    await tester.pump(codexHoverPopupDelay);
    await tester.pump();
    expect(find.text('2 个任务'), findsOneWidget);
    await tester.tap(find.byTooltip('置顶项目'));
    await tester.pumpAndSettle();
    expect(controller.isWorkspacePinned(firstPath), isTrue);
    expect(runtimeStore.savedPinnedWorkspaces, {firstPath});
    expect(find.byTooltip('取消置顶项目'), findsOneWidget);
    await tester.tap(moreButton);
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('创建永久工作树'), findsOneWidget);
    expect(find.text('归档聊天'), findsOneWidget);
    expect(find.text('移除项目'), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('workspace-directories-dialog')),
      findsOneWidget,
    );
    final projectNameField = tester.widget<TextField>(
      find.byKey(const Key('workspace-project-name-field')),
    );
    final projectNameDecoration = projectNameField.decoration!;
    expect(projectNameDecoration.filled, isFalse);
    expect(projectNameDecoration.border, InputBorder.none);
    expect(projectNameDecoration.enabledBorder, InputBorder.none);
    expect(projectNameDecoration.focusedBorder, InputBorder.none);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    controller
      ..activeThreadId = 'nested-task'
      ..status = RuntimeStatus.ready
      ..notifyListeners();
    await tester.pump();
    await mouse.moveTo(tester.getCenter(firstTile));
    await tester.pump();
    // Cross-project creation is covered by the dedicated regression test;
    // keep this sidebar rendering test focused on row affordances.
    controller.createThread();
    controller
      ..activeThreadId = 'nested-task'
      ..status = RuntimeStatus.running
      ..notifyListeners();
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(
        const Key('sidebar-running-task-indicator'),
        skipOffstage: false,
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('sidebar-running-task-indicator')),
      findsOneWidget,
    );
    final runningTaskIndicator = tester.widget<SizedBox>(
      find.byKey(const Key('sidebar-running-task-indicator')),
    );
    expect(runningTaskIndicator.width, 10);
    expect(runningTaskIndicator.height, 10);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.descendant(
              of: find.byKey(const Key('sidebar-running-task-indicator')),
              matching: find.byType(CircularProgressIndicator),
            ),
          )
          .strokeWidth,
      1.25,
    );
    expect(
      tester
          .widget<InkWell>(
            find.ancestor(
              of: find.descendant(
                of: find.byKey(const Key('sidebar-pane')),
                matching: find.text('preview-nested-task'),
              ),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNotNull,
    );
    expect(
      find.byKey(const Key('sidebar-create-workspace-button')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('sidebar-create-workspace-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.byKey(const Key('sidebar-manage-workspaces-button')),
      findsOneWidget,
    );
    // 启动后，未选中的项目也会从本地缓存读取任务并保持展开；
    // 整个项目行与左侧文件夹图标都只改变该项目的展开状态。
    await tester.ensureVisible(
      find.byKey(ValueKey('sidebar-workspace-$firstPath'), skipOffstage: false),
    );
    await tester.pump();
    final cachedFirstTask = find.text(
      'preview-cached-first-task',
      skipOffstage: false,
    );
    expect(cachedFirstTask, findsOneWidget);
    final firstFolder = find.byKey(
      ValueKey('sidebar-workspace-folder-$firstPath'),
      skipOffstage: false,
    );
    expect(firstFolder, findsOneWidget);
    final folderSwitcher = find.descendant(
      of: find.byKey(
        ValueKey('sidebar-workspace-$firstPath'),
        skipOffstage: false,
      ),
      matching: find.byType(AnimatedSwitcher),
      skipOffstage: false,
    );
    expect(folderSwitcher, findsOneWidget);
    expect(
      tester.widget<AnimatedSwitcher>(folderSwitcher).duration,
      const Duration(milliseconds: 180),
    );
    expect(
      find.descendant(of: firstFolder, matching: find.byType(SvgPicture)),
      findsOneWidget,
    );
    final activePathBeforeFolderTap = controller.workspacePath;
    await tester.tap(firstTile);
    await tester.pump();
    expect(controller.workspacePath, activePathBeforeFolderTap);
    expect(tester.widget<SidebarWorkspaceTile>(firstTile).expanded, isFalse);
    final collapsedFolder = find.descendant(
      of: find.descendant(
        of: firstTile,
        matching: find.byKey(const ValueKey(false)),
      ),
      matching: find.byKey(ValueKey('sidebar-workspace-folder-$firstPath')),
    );
    expect(
      find.descendant(of: collapsedFolder, matching: find.byType(SvgPicture)),
      findsOneWidget,
    );
    await tester.tap(firstTile);
    await tester.pump();
    expect(controller.workspacePath, activePathBeforeFolderTap);
    expect(tester.widget<SidebarWorkspaceTile>(firstTile).expanded, isTrue);
    expect(cachedFirstTask, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('creates a project from a dragged source folder', (tester) async {
    late Directory root;
    late Directory source;
    late Directory additional;
    late CodexController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp(
        'codex-desk-create-project-',
      );
      source = await Directory('${root.path}/project-source').create();
      additional = await Directory('${root.path}/project-additional').create();
      controller = CodexController(server: ManagedRuntimeFakeServer());
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.stopped;
    });
    addTearDown(() => root.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('sidebar-create-workspace-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create-workspace-dialog')), findsOneWidget);
    expect(
      find.byKey(const Key('create-workspace-dialog-title')),
      findsOneWidget,
    );
    expect(find.text('项目名称'), findsOneWidget);
    expect(find.text('添加 Codex 可读取和编辑的文件夹'), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const Key('create-workspace-folder-picker')),
          )
          .onTap,
      isNotNull,
    );

    var dropTarget = tester.widget<DropTarget>(
      find.byKey(const Key('create-workspace-folder-drop-target')),
    );
    dropTarget.onDragEntered?.call(
      DropEventDetails(
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pump();
    expect(find.text('松开即可添加文件夹'), findsOneWidget);

    dropTarget = tester.widget<DropTarget>(
      find.byKey(const Key('create-workspace-folder-drop-target')),
    );
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemDirectory(source.path, const [])],
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('project-source'), findsOneWidget);

    // Once the primary folder is selected, the same drop target remains
    // available for appending additional source folders.
    dropTarget = tester.widget<DropTarget>(
      find.byKey(const Key('create-workspace-folder-drop-target')),
    );
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemDirectory(additional.path, const [])],
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('project-source'), findsOneWidget);
    expect(find.text('project-additional'), findsOneWidget);
    expect(
      find.byKey(const Key('add-workspace-directory-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('cancel-create-workspace')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create-workspace-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps project creation available during a task and saves it inactive',
    (tester) async {
      late Directory root;
      late Directory createdDirectory;
      late String activePath;
      late String createdPath;
      late ManagedRuntimeFakeServer server;
      late CodexController controller;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp(
          'codex-desk-running-create-project-',
        );
        final activeDirectory = await Directory('${root.path}/active').create();
        createdDirectory = await Directory('${root.path}/created').create();
        activePath = await activeDirectory.resolveSymbolicLinks();
        createdPath = await createdDirectory.resolveSymbolicLinks();
        server = ManagedRuntimeFakeServer();
        controller = CodexController(
          server: server,
          runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
          conversationHistoryStore: MemoryConversationHistoryStore(),
        );
        await controller.waitForInitialConfiguration();
        await controller.selectWorkspaceAndReconnect(activeDirectory.path);
        controller
          ..status = RuntimeStatus.running
          ..activeThreadId = 'running-thread';
      });
      addTearDown(() => root.delete(recursive: true));

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      final createButton = find.byKey(
        const Key('sidebar-create-workspace-button'),
      );
      expect(tester.widget<IconButton>(createButton).onPressed, isNotNull);
      await tester.runAsync(() async {
        expect(
          await controller.createWorkspace(
            createdDirectory.path,
            name: '任务中创建的项目',
          ),
          isTrue,
        );
      });
      await tester.pump();

      expect(
        controller.workspaceConfigurations.any(
          (workspace) => workspace.primaryPath == createdPath,
        ),
        isTrue,
        reason: controller.lastError,
      );
      expect(controller.workspacePath, activePath);
      expect(controller.activeThreadId, 'running-thread');
      expect(controller.status, RuntimeStatus.running);
      expect(server.startCalls, 1);
      expect(server.stopCalls, 0);
      expect(find.text('任务中创建的项目'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('sidebar-manage-workspaces-button')),
      );
      await tester.pump();
      final switchButton = tester.widget<TextButton>(
        find.byKey(ValueKey('switch-workspace-$createdPath')),
      );
      expect(switchButton.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'keeps a viewed completion hidden after its workspace becomes inactive',
    (tester) async {
      late Directory root;
      late String firstPath;
      late String secondPath;
      late CodexController controller;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp(
          'codex-desk-inactive-completion-',
        );
        final first = await Directory('${root.path}/first').create();
        final second = await Directory('${root.path}/second').create();
        firstPath = await first.resolveSymbolicLinks();
        secondPath = await second.resolveSymbolicLinks();
        final runtimeStore = FakeRuntimeConfigurationStore()
          ..workspace = secondPath
          ..workspaces = [
            WorkspaceConfiguration(
              id: 'inactive-completion-first',
              primaryPath: firstPath,
            ),
            WorkspaceConfiguration(
              id: 'inactive-completion-second',
              primaryPath: secondPath,
            ),
          ];
        historyStore.snapshots['inactive-completion-first'] =
            ConversationHistorySnapshot(
              threads: [threadForTest(id: 'viewed-completed', status: 'idle')],
              archivedThreads: const [],
              entries: const [],
              fileChanges: const [],
              acknowledgedCompletedThreadIds: const {'viewed-completed'},
            );
        controller = CodexController(
          server: CodexAppServer(),
          runtimeConfigurationStore: runtimeStore,
          conversationHistoryStore: historyStore,
        );
        await controller.waitForInitialConfiguration();
        await controller.refreshInactiveWorkspaceTaskLists();
      });
      addTearDown(() => root.delete(recursive: true));

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(find.text('preview-viewed-completed'), findsOneWidget);
      expect(
        find.byKey(const Key('sidebar-completed-task-indicator')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
