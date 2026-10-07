import 'dart:async';
import 'widget_test_fakes.dart';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_side_panel_tabs.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _FakeRuntimeConfigurationStore = FakeRuntimeConfigurationStore;
typedef _MemoryConversationHistoryStore = MemoryConversationHistoryStore;
typedef _FakeGitProjectService = FakeGitProjectService;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('opens Git workspace changes in the embedded review surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const change = GitProjectChange(code: ' M', path: 'lib/editor.dart');
    final git = _FakeGitProjectService()
      ..status = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: [change],
      )
      ..diff =
          'diff --git a/lib/editor.dart b/lib/editor.dart\n'
          '--- a/lib/editor.dart\n'
          '+++ b/lib/editor.dart\n'
          '@@ -2 +2 @@\n-old\n+workspace';
    final controller =
        CodexController(server: CodexAppServer(), gitProjectService: git)
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('codex-environment-card')),
        matching: find.text('本地'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('code-review-panel')), findsOneWidget);
    expect(find.text('Git 工作区'), findsOneWidget);
    expect(find.text('lib/editor.dart'), findsOneWidget);
    expect(find.text('+workspace'), findsOneWidget);
    expect(
      controller.gitReviewDiffs['lib/editor.dart']?.content,
      contains('+workspace'),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps diff canvas valid through extremely narrow widths', (
    tester,
  ) async {
    final horizontalController = ScrollController();
    addTearDown(horizontalController.dispose);

    for (final width in <double>[15.2, 44, 88]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 80,
              child: CustomScrollView(
                primary: false,
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: ReviewFileHeaderDelegate(
                      key: GlobalKey(),
                      file: const ReviewFile(
                        path: 'lib/a_very_long_file_name.dart',
                        kind: 'modified',
                        diff: '+a long diff line',
                        truncated: true,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: ReviewDiffRow(
                      row: const ReviewRow(
                        ReviewRowKind.addition,
                        '+a long diff line',
                        oldLine: 1,
                        newLine: 2,
                      ),
                      horizontalController: horizontalController,
                      contentWidth: 520,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'width: $width');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps side panel tabs valid through transition widths', (
    tester,
  ) async {
    for (final width in <double>[15.2, 40, 52, 66, 72]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 160,
              child: WorkspaceSidePanelTabs(
                contents: const {'review': SizedBox()},
                labels: const {'review': '审查'},
                activeTab: 'review',
                onSelect: (_) {},
                onCollapse: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'width: $width');
      expect(find.byKey(const Key('side-panel-collapse')), findsOneWidget);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the complete review panel valid at transition widths', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;

    for (final width in <double>[4.5, 15.2, 17, 40, 52]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 900,
              child: CodeReviewPanel(
                controller: controller,
                source: CodeReviewSource.latestTurn,
                compact: true,
                onSourceChanged: (_) {},
                onCollapse: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'width: $width');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps Git review actions accessible in a narrow toolbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const change = GitProjectChange(code: ' M', path: 'lib/editor.dart');
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..gitProjectStatus = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: [change],
      )
      ..gitReviewDiffs = const {
        'lib/editor.dart': GitDiffPreview(
          content: '@@ -1 +1 @@\n-old\n+new',
          truncated: false,
        ),
      };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: CodeReviewPanel(
                controller: controller,
                source: CodeReviewSource.gitWorkspace,
                compact: true,
                onSourceChanged: (_) {},
                onCollapse: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('code-review-commit')), findsNothing);
    await tester.tap(find.byKey(const Key('code-review-more-menu')));
    await tester.pumpAndSettle();

    expect(find.text('提交或推送'), findsOneWidget);
    expect(find.text('创建拉取请求'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps Git dialog fields alive through their exit animations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..gitProjectStatus = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeReviewPanel(
            controller: controller,
            source: CodeReviewSource.gitWorkspace,
            compact: true,
            onSourceChanged: (_) {},
            onCollapse: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('code-review-more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交或推送'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test commit');
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('code-review-more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建拉取请求'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test pull request');
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reveals the selected file when compact navigation reopens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              for (var index = 0; index < 40; index++)
                {
                  'path': 'lib/file_${index.toString().padLeft(2, '0')}.dart',
                  'kind': 'modified',
                  'diff': '@@ -1 +1 @@\n-old\n+new',
                },
            ],
          },
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeReviewPanel(
            controller: controller,
            source: CodeReviewSource.latestTurn,
            compact: true,
            onSourceChanged: (_) {},
            onCollapse: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
    await tester.pump();
    final tree = find.byKey(const Key('code-review-file-tree'));
    await tester.drag(tree, const Offset(0, -5000));
    await tester.pump();
    const lastPath = 'lib/file_39.dart';
    final lastRow = find.byKey(const ValueKey('code-review-file-$lastPath'));
    expect(lastRow, findsOneWidget);
    await tester.tap(lastRow);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('code-review-selected-path-$lastPath')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
    await tester.pump();
    await tester.drag(tree, const Offset(0, 5000));
    await tester.pump();
    await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('code-review-selected-path-$lastPath')),
      findsOneWidget,
    );

    final overlayRect = tester.getRect(
      find.byKey(const Key('review-navigation-overlay')),
    );
    final selectedRect = tester.getRect(lastRow);
    expect(selectedRect.top, greaterThanOrEqualTo(overlayRect.top));
    expect(selectedRect.bottom, lessThanOrEqualTo(overlayRect.bottom));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'locks Git review writes and shows progress only on the source row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const change = GitProjectChange(code: ' M', path: 'lib/editor.dart');
      final git = _FakeGitProjectService()
        ..status = const GitProjectStatus(
          isRepository: true,
          branch: 'main',
          changes: [change],
        )
        ..diff = '@@ -1 +1 @@\n-old\n+new'
        ..stageCompleter = Completer<void>();
      final controller =
          CodexController(server: CodexAppServer(), gitProjectService: git)
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('codex-environment-card')),
          matching: find.text('本地'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
      await tester.pump();
      final row = find.byKey(
        const ValueKey('code-review-file-lib/editor.dart'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.moveTo(tester.getCenter(row));
      await tester.pump();
      await tester.tap(find.byTooltip('暂存文件'));
      await tester.pump();

      expect(git.stageCalls, 1);
      expect(controller.gitOperationRunning, isTrue);
      expect(
        find.byKey(const Key('code-review-file-operation')),
        findsOneWidget,
      );

      git.stageCompleter!.complete();
      await tester.pumpAndSettle();
      expect(controller.gitOperationRunning, isFalse);
      expect(find.byKey(const Key('code-review-file-operation')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mouse.removePointer();
    },
  );

  testWidgets('reports a failed Git review operation without closing review', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const change = GitProjectChange(code: ' M', path: 'lib/editor.dart');
    final git = _FakeGitProjectService()
      ..status = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: [change],
      )
      ..diff = '@@ -1 +1 @@\n-old\n+new'
      ..stageError = StateError('暂存被拒绝');
    final controller =
        CodexController(server: CodexAppServer(), gitProjectService: git)
          ..workspacePath = '/workspace'
          ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('codex-environment-card')),
        matching: find.text('本地'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
    await tester.pump();
    final row = find.byKey(const ValueKey('code-review-file-lib/editor.dart'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump();
    await tester.tap(find.byTooltip('暂存文件'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂存被拒绝'), findsOneWidget);
    expect(find.byKey(const Key('code-review-panel')), findsOneWidget);
    expect(controller.gitOperationRunning, isFalse);
    await tester.pumpWidget(const SizedBox());
    await mouse.removePointer();
  });

  testWidgets('resizes the side panes through their drag handles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = CodexController(server: CodexAppServer())
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final sidebar = find.byKey(const Key('sidebar-pane'));
    final environmentCard = find.byKey(const Key('codex-environment-card'));
    final initialSidebarWidth = tester.getSize(sidebar).width;
    final initialInspectorWidth = tester.getSize(environmentCard).width;

    await tester.drag(
      find.byKey(const Key('sidebar-resize-handle')),
      const Offset(72, 0),
    );
    await tester.pump();
    expect(tester.getSize(sidebar).width, greaterThan(initialSidebarWidth));

    await tester.drag(
      find.byKey(const Key('inspector-resize-handle')),
      const Offset(-72, 0),
    );
    await tester.pump();
    expect(
      tester.getSize(environmentCard).width,
      greaterThan(initialInspectorWidth),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens the Git project workflow view', (tester) async {
    const change = GitProjectChange(code: '??', path: 'new_file.txt');
    final git = _FakeGitProjectService()
      ..status = const GitProjectStatus(
        isRepository: true,
        branch: 'main',
        changes: [
          change,
          GitProjectChange(code: ' M', path: 'lib/editor.dart'),
        ],
      )
      ..diff = 'preview\n\n${GitProjectService.truncatedDiffMarker}';
    final controller = CodexController(
      server: CodexAppServer(),
      gitProjectService: git,
    )..workspacePath = '/workspace';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.text('Git 项目'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('git-project-dialog')), findsOneWidget);
    expect(find.text('分支：main'), findsOneWidget);
    expect(find.text('选择文件可查看 Diff、暂存或还原；提交、推送和创建 PR 均需显式确认。'), findsOneWidget);
    expect(find.byKey(const Key('git-change-search')), findsOneWidget);
    expect(find.byKey(const Key('git-change-filter')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('git-change-search')),
      'editor',
    );
    await tester.pump();

    expect(find.text('lib/editor.dart'), findsOneWidget);
    expect(find.text('new_file.txt'), findsNothing);

    await tester.enterText(find.byKey(const Key('git-change-search')), '');
    await tester.pump();
    await tester.tap(find.text('new_file.txt'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('git-diff-truncated-warning')), findsOneWidget);
  });
}
