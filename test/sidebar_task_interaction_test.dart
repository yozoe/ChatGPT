import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('searches tasks from the top toolbar command surface', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [threadForTest(id: 'alpha'), threadForTest(id: 'bravo')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final taskTile = find.byKey(const ValueKey('sidebar-thread-tile-alpha'));
    final taskContent = tester.widget<Padding>(
      find.descendant(of: taskTile, matching: find.byType(Padding)).first,
    );
    expect(taskContent.padding, const EdgeInsets.fromLTRB(30, 4, 8, 4));

    expect(find.byKey(const Key('thread-search-field')), findsNothing);
    await tester.tap(find.byKey(const Key('task-search-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-search-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('task-search-dialog-field')),
      'bravo',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('task-search-result-bravo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task-search-result-alpha')),
      findsNothing,
    );
    expect(find.text('新聊天'), findsOneWidget);
    expect(find.text('打开文件夹'), findsOneWidget);
    expect(find.text('搜索文件'), findsOneWidget);
  });

  testWidgets('centers task title vertically within its sidebar row', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [threadForTest(id: 'vertical-center-task')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final tile = find.byKey(
      const ValueKey('sidebar-thread-tile-vertical-center-task'),
    );
    final title = find.byKey(
      const ValueKey('sidebar-thread-title-fade-vertical-center-task'),
    );
    final tileRect = tester.getRect(tile);
    final titleRect = tester.getRect(title);
    expect(titleRect.center.dy, closeTo(tileRect.center.dy, 0.5));
    expect(tileRect.height, closeTo(32, 0.1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'shows task hover shortcuts and opens task actions on right click',
    (tester) async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready
        ..threads = [threadForTest(id: 'alpha', status: 'idle')];
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      final taskTile = find.byKey(const ValueKey('sidebar-thread-tile-alpha'));
      expect(
        find.byKey(const ValueKey('sidebar-thread-pin-alpha')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sidebar-thread-archive-alpha')),
        findsNothing,
      );
      expect(
        find.descendant(of: taskTile, matching: find.byType(PopupMenuButton)),
        findsNothing,
      );
      final completedIndicator = tester.widget<Icon>(
        find.byKey(const Key('sidebar-completed-task-indicator')),
      );
      expect(completedIndicator.icon, Icons.circle);
      expect(completedIndicator.size, 6);
      expect(completedIndicator.color, const Color(0xFF0A84FF));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.moveTo(tester.getCenter(taskTile));
      await tester.pump();
      expect(
        find.byKey(const Key('sidebar-completed-task-indicator')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sidebar-thread-pin-alpha')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sidebar-thread-archive-alpha')),
        findsOneWidget,
      );

      final contextMenuMouse = await tester.createGesture(
        pointer: 2,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await contextMenuMouse.down(tester.getCenter(taskTile));
      await contextMenuMouse.up();
      await tester.pumpAndSettle();
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('归档'), findsOneWidget);
      expect(find.text('永久删除'), findsOneWidget);

      await tester.tap(find.text('置顶'));
      await tester.pump();
      expect(controller.isThreadPinned('alpha'), isTrue);
    },
  );

  testWidgets('keeps the task list visible while a selected task refreshes', (
    tester,
  ) async {
    final server = FakeCodexAppServer()
      ..queueListRequests = true
      ..listResponse = [
        {'id': 'alpha', 'preview': 'preview-alpha'},
        {'id': 'bravo', 'preview': 'preview-bravo'},
      ];
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..threads = [threadForTest(id: 'alpha'), threadForTest(id: 'bravo')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.text('preview-alpha'));
    await tester.pump();

    expect(controller.threadsLoading, isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-pane')),
        matching: find.text('preview-alpha'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-pane')),
        matching: find.text('preview-bravo'),
      ),
      findsOneWidget,
    );

    server.listRequests.single.complete(server.listResponse);
    await tester.pumpAndSettle();
  });
}
