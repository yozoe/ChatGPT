import 'dart:async';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_submission.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  testWidgets(
    'searches workspace files from the mention menu and attaches one',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const root = '/workspace';
      const sourcePath =
          '/workspace/lib/a_very_long_nested_folder_name/main.dart';
      final controller = WorkspaceFileSearchController()
        ..workspacePath = root
        ..status = RuntimeStatus.ready
        ..response = const [
          CodexFileSearchResult(
            fileName: 'main.dart',
            path: sourcePath,
            root: root,
            matchType: 'file',
            score: 100,
            indices: [0, 1, 2, 3],
          ),
        ];
      final composer = TextEditingController();
      ComposerSubmission? submission;
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
              onSend: (value) async {
                submission = value;
                return true;
              },
              onQueueSteer: (_) async => false,
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('composer-field')), '@main');
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pump();

      expect(controller.queries, ['main']);
      expect(controller.rootsAtRequest.single, [root]);
      expect(find.text('main.dart'), findsOneWidget);
      expect(
        find.textContaining('a_very_long_nested_folder_name'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('main.dart'));
      await tester.pump();
      expect(
        find.byKey(ValueKey('composer-attachment-$sourcePath')),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('composer-field')), '检查入口');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(submission?.attachments, hasLength(1));
      expect(submission?.attachments.single.path, sourcePath);
      expect(submission?.attachments.single.isDirectory, isFalse);
    },
  );

  testWidgets('ignores stale fuzzy file results after the query changes', (
    tester,
  ) async {
    const root = '/workspace';
    final firstRequest = Completer<List<CodexFileSearchResult>>();
    final secondRequest = Completer<List<CodexFileSearchResult>>();
    final controller = WorkspaceFileSearchController()
      ..workspacePath = root
      ..status = RuntimeStatus.ready
      ..completers.addAll([firstRequest, secondRequest]);
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

    await tester.enterText(find.byKey(const Key('composer-field')), '@first');
    await tester.pump(const Duration(milliseconds: 121));
    expect(controller.queries, ['first']);

    await tester.enterText(find.byKey(const Key('composer-field')), '@second');
    await tester.pump(const Duration(milliseconds: 121));
    expect(controller.queries, ['first', 'second']);

    secondRequest.complete(const [
      CodexFileSearchResult(
        fileName: 'second.dart',
        path: '/workspace/second.dart',
        root: root,
        matchType: 'file',
        score: 20,
        indices: [],
      ),
    ]);
    await tester.pump();
    expect(find.text('second.dart'), findsAtLeastNWidgets(1));

    firstRequest.complete(const [
      CodexFileSearchResult(
        fileName: 'first.dart',
        path: '/workspace/first.dart',
        root: root,
        matchType: 'file',
        score: 10,
        indices: [],
      ),
    ]);
    await tester.pump();

    expect(find.text('second.dart'), findsAtLeastNWidgets(1));
    expect(find.text('first.dart'), findsNothing);

    await tester.tap(find.byKey(const Key('composer-field')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-attachment-/workspace/second.dart')),
      findsOneWidget,
    );
  });

  testWidgets('ignores fuzzy file results from a previous workspace', (
    tester,
  ) async {
    final firstRequest = Completer<List<CodexFileSearchResult>>();
    final secondRequest = Completer<List<CodexFileSearchResult>>();
    final controller = WorkspaceFileSearchController()
      ..workspacePath = '/workspace-a'
      ..status = RuntimeStatus.ready
      ..completers.addAll([firstRequest, secondRequest]);
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

    await tester.enterText(find.byKey(const Key('composer-field')), '@shared');
    await tester.pump(const Duration(milliseconds: 121));
    expect(controller.rootsAtRequest, [
      ['/workspace-a'],
    ]);

    controller.workspacePath = '/workspace-b';
    controller.notifyListeners();
    await tester.pump(const Duration(milliseconds: 121));
    expect(controller.rootsAtRequest, [
      ['/workspace-a'],
      ['/workspace-b'],
    ]);

    firstRequest.complete(const [
      CodexFileSearchResult(
        fileName: 'old.dart',
        path: '/workspace-a/old.dart',
        root: '/workspace-a',
        matchType: 'file',
        score: 10,
        indices: [],
      ),
    ]);
    await tester.pump();
    expect(find.text('old.dart'), findsNothing);

    secondRequest.complete(const [
      CodexFileSearchResult(
        fileName: 'current.dart',
        path: '/workspace-b/current.dart',
        root: '/workspace-b',
        matchType: 'file',
        score: 20,
        indices: [],
      ),
    ]);
    await tester.pump();
    expect(find.text('current.dart'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows fuzzy file loading and retryable error states', (
    tester,
  ) async {
    final pending = Completer<List<CodexFileSearchResult>>();
    final controller = WorkspaceFileSearchController()
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..completers.add(pending);
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

    await tester.enterText(find.byKey(const Key('composer-field')), '@missing');
    await tester.pump(const Duration(milliseconds: 121));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('composer-mention-menu')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    pending.completeError(StateError('search failed'));
    await tester.pump();
    expect(find.text('无法搜索项目文件，请重试。'), findsOneWidget);
  });
}
