import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_conversation_pane.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<dynamic> resolveLastAgentMarkdownLinks(WidgetTester tester) async {
  final markdown = find
      .byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'AgentMarkdown',
      )
      .last;
  final state = tester.state(markdown) as dynamic;
  await tester.runAsync(
    () => state.resolveLocalLinksForTesting() as Future<void>,
  );
  await tester.pump();
  return state;
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 50,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
}

void main() {
  testWidgets('opens project Markdown links as retained workspace tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Directory workspace;
    late File document;
    late String documentPath;
    late String nextDocumentPath;
    await tester.runAsync(() async {
      workspace = await Directory.systemTemp.createTemp(
        'codex-desk-markdown-preview-',
      );
      final guideDirectory = Directory('${workspace.path}/guide');
      await guideDirectory.create();
      document = File('${workspace.path}/product notes.md');
      await document.writeAsString(
        '# 产品说明\n\n[阅读下一页](guide/next.md)\n\n- 格式化条目\n\n'
        '${List<String>.filled(5000, 'x').join()}',
      );
      final nextDocument = File('${guideDirectory.path}/next.md');
      await nextDocument.writeAsString('# 下一页标题\n\n返回后继续阅读。');
      documentPath = await document.resolveSymbolicLinks();
      nextDocumentPath = await nextDocument.resolveSymbolicLinks();
    });
    addTearDown(() => workspace.delete(recursive: true));

    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = workspace.path;
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'item/agentMessage/delta',
        params: {
          'itemId': 'markdown-file-message',
          'delta': '[打开文档](${document.uri}:3)',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 60));

    await resolveLastAgentMarkdownLinks(tester);
    final fileRow = find
        .ancestor(
          of: find.text('product notes.md'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(fileRow, findsOneWidget);

    final documentTab = ValueKey('side-panel-tab-file:$documentPath');
    final documentPage = ValueKey('markdown-workspace-page-$documentPath');
    tester.widget<InkWell>(fileRow).onTap!();
    await pumpUntilFound(tester, find.byKey(documentTab));
    await pumpUntilFound(tester, find.text('产品说明'));

    expect(find.byKey(const Key('markdown-preview-dialog')), findsNothing);
    expect(find.byKey(documentTab), findsOneWidget);
    expect(find.byKey(documentPage), findsOneWidget);
    expect(find.byType(ConversationPane), findsOneWidget);
    expect(find.byKey(const Key('markdown-preview-file-name')), findsOneWidget);
    expect(find.text('L3'), findsOneWidget);
    expect(find.text('产品说明'), findsOneWidget);
    expect(find.text('格式化条目'), findsOneWidget);

    await tester.tap(find.text('阅读下一页'));
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(ValueKey('side-panel-tab-file:$nextDocumentPath')),
    );
    expect(
      find.byKey(ValueKey('side-panel-tab-file:$nextDocumentPath')),
      findsOneWidget,
    );
    await pumpUntilFound(tester, find.text('下一页标题'));
    expect(find.text('下一页标题'), findsOneWidget);

    await tester.tap(find.byKey(documentTab));
    await tester.pump();
    expect(find.text('产品说明'), findsOneWidget);

    await tester.tap(find.byKey(const Key('markdown-source-mode-button')));
    await tester.pump();
    expect(find.byKey(const Key('markdown-source-view')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('markdown-source-line-3')),
      findsOneWidget,
    );
    expect(find.textContaining('此行过长，已截断显示'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('markdown-source-content'))).width,
      lessThan(40000),
    );

    await tester.tap(
      find.byKey(ValueKey('side-panel-tab-close-file:$documentPath')),
    );
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byKey(documentTab), findsNothing);
    expect(
      find.byKey(ValueKey('side-panel-tab-file:$nextDocumentPath')),
      findsOneWidget,
    );
    await pumpUntilFound(tester, find.text('下一页标题'));
    expect(find.text('下一页标题'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens other project text files in source workspace tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(680, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Directory workspace;
    late Directory nextWorkspace;
    late File document;
    late String documentPath;
    await tester.runAsync(() async {
      workspace = await Directory.systemTemp.createTemp(
        'codex-desk-source-preview-',
      );
      nextWorkspace = await Directory.systemTemp.createTemp(
        'codex-desk-source-preview-next-',
      );
      document = File('${workspace.path}/example.dart');
      await document.writeAsString('const message = "before";');
      documentPath = await document.resolveSymbolicLinks();
    });
    addTearDown(() async {
      await workspace.delete(recursive: true);
      await nextWorkspace.delete(recursive: true);
    });

    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = workspace.path
      ..replaceTimelineEntriesForTesting([
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '[example.dart](${document.uri})',
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await resolveLastAgentMarkdownLinks(tester);

    final fileRow = find
        .ancestor(of: find.text('example.dart'), matching: find.byType(InkWell))
        .first;
    tester.widget<InkWell>(fileRow).onTap!();
    await pumpUntilFound(
      tester,
      find.byKey(ValueKey('side-panel-tab-file:$documentPath')),
    );

    expect(
      find.byKey(ValueKey('side-panel-tab-file:$documentPath')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('source-workspace-page-$documentPath')),
      findsOneWidget,
    );
    await pumpUntilFound(tester, find.textContaining('before'));
    expect(find.textContaining('before'), findsOneWidget);
    expect(find.byType(ConversationPane), findsOneWidget);
    final source = tester.widget<SelectableText>(
      find.byKey(const Key('source-workspace-content')),
    );
    expect(source.style?.fontFamily, 'monospace');
    expect(source.style?.fontSize, 12);
    expect(source.style?.height, 1.5);

    await tester.runAsync(
      () => document.writeAsString('const message = "after";'),
    );
    tester.widget<InkWell>(fileRow).onTap!();
    await pumpUntilFound(tester, find.textContaining('after'));
    expect(find.textContaining('after'), findsOneWidget);
    expect(find.textContaining('before'), findsNothing);

    controller.workspacePath = nextWorkspace.path;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('side-panel-tab-file:$documentPath')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('source-workspace-page-$documentPath')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
