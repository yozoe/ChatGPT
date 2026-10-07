import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<dynamic> _resolveLastAgentMarkdownLinks(WidgetTester tester) async {
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

void main() {
  testWidgets('renders Codex replies as selectable Markdown', (tester) async {
    final controller = CodexController(server: CodexAppServer());
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {
          'itemId': 'markdown-message',
          'delta': '- **严重**：加密缓存每次保存会丢掉其他项目的历史。',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 60));

    final selectionArea = find.byKey(const Key('agent-markdown-selection'));
    expect(selectionArea, findsOneWidget);
    expect(
      find.descendant(of: selectionArea, matching: find.byType(Scrollable)),
      findsNothing,
    );
    final renderedText = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('严重'),
    );
    expect(renderedText, findsOneWidget);
    final text = tester.widget<RichText>(renderedText).text;
    expect(text.toPlainText(), contains('严重'));
    expect(text.toPlainText(), isNot(contains('**')));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preserves nested formatting inside ordinary Markdown links', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/agentMessage/delta',
        params: {
          'itemId': 'formatted-link-message',
          'delta': '[**重要** 与 `code`](https://example.com)',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 60));

    final linkText = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.textSpan?.toPlainText() == '重要 与 code',
      ),
    );
    final spans = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is! TextSpan) return;
      spans.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        collect(child);
      }
    }

    collect(linkText.textSpan!);
    expect(
      spans.singleWhere((span) => span.text == '重要').style?.fontWeight,
      FontWeight.w700,
    );
    expect(
      spans.singleWhere((span) => span.text == 'code').style?.fontFamily,
      'monospace',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps linked local images inside the workspace and exposes their alt text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      late Directory workspace;
      late Directory outside;
      late File insideImage;
      late File outsideImage;
      late String insideImagePath;
      late String outsideImagePath;
      await tester.runAsync(() async {
        workspace = await Directory.systemTemp.createTemp(
          'codex-desk-linked-image-',
        );
        outside = await Directory.systemTemp.createTemp(
          'codex-desk-linked-image-outside-',
        );
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
          'A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        insideImage = File('${workspace.path}/inside.png');
        outsideImage = File('${outside.path}/outside.png');
        await insideImage.writeAsBytes(png);
        await outsideImage.writeAsBytes(png);
        insideImagePath = await insideImage.resolveSymbolicLinks();
        outsideImagePath = await outsideImage.resolveSymbolicLinks();
      });
      addTearDown(() async {
        await workspace.delete(recursive: true);
        await outside.delete(recursive: true);
      });

      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = workspace.path;
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'itemId': 'linked-local-images',
            'delta':
                '[![项目内图片](${insideImage.uri})](https://example.com/inside) '
                '[![项目外图片](${outsideImage.uri})](https://example.com/outside)',
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      final linkedImages = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'AgentLinkedImage',
      );
      for (final element in linkedImages.evaluate()) {
        final state =
            tester.state(
                  find.byElementPredicate((candidate) => candidate == element),
                )
                as dynamic;
        await tester.runAsync(() => state.resolveForTesting() as Future<void>);
      }
      await tester.pump();

      final fileImages = tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is FileImage)
          .map((image) => (image.image as FileImage).file.path)
          .toList();
      expect(fileImages, [insideImagePath]);
      expect(fileImages, isNot(contains(outsideImagePath)));
      expect(find.text('项目外图片'), findsOneWidget);
      expect(find.bySemanticsLabel('项目内图片'), findsOneWidget);
      expect(find.bySemanticsLabel('项目外图片'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets('renders project files as compact conversation file rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Directory workspace;
    late Directory outside;
    late File artifact;
    late File outsideFile;
    late String artifactPath;
    await tester.runAsync(() async {
      workspace = await Directory.systemTemp.createTemp(
        'codex-desk-agent-file-row-',
      );
      outside = await Directory.systemTemp.createTemp(
        'codex-desk-agent-file-row-outside-',
      );
      final buildDirectory = Directory('${workspace.path}/build/output');
      await buildDirectory.create(recursive: true);
      artifact = File(
        '${buildDirectory.path}/codex_workspace_extensions_plugins_page_state.dart',
      );
      outsideFile = File('${outside.path}/secret.zip');
      await artifact.writeAsBytes(const [0, 1, 2]);
      await outsideFile.writeAsBytes(const [3, 4, 5]);
      artifactPath = await artifact.resolveSymbolicLinks();
      final reference = await resolveWorkspaceFileReference(
        href: artifact.uri.toString(),
        workspacePath: workspace.path,
      );
      expect(reference?.path, artifactPath);
    });
    addTearDown(() async {
      await workspace.delete(recursive: true);
      await outside.delete(recursive: true);
    });

    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = workspace.path;
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'item/agentMessage/delta',
        params: {
          'itemId': 'artifact-message',
          'delta':
              '- **文件：**  \n  [download](${artifact.uri})'
              '\n\n[项目外文件](${outsideFile.uri})',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await _resolveLastAgentMarkdownLinks(tester);

    final fileRow = find.ancestor(
      of: find.text('codex_workspace_extensions_plugins_page_state.dart'),
      matching: find.byType(InkWell),
    );
    expect(fileRow, findsOneWidget);
    final fileName = tester.widget<Text>(
      find.text('codex_workspace_extensions_plugins_page_state.dart'),
    );
    expect(fileName.maxLines, isNull);
    expect(fileName.overflow, isNot(TextOverflow.ellipsis));
    expect(
      find.descendant(
        of: fileRow,
        matching: find.byIcon(Icons.insert_drive_file_outlined),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(fileRow).width, greaterThan(360));
    expect(find.text('项目外文件'), findsOneWidget);
    final leadText = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('文件：'),
    );
    final leadRect = tester.getRect(leadText);
    final fileRect = tester.getRect(fileRow);
    expect(fileRect.left, closeTo(leadRect.left, 0.5));
    expect(fileRect.top, greaterThanOrEqualTo(leadRect.bottom));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'upgrades all local file links in one completed reply as one batch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(680, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late Directory workspace;
      late File controllerFile;
      late File specificationFile;
      await tester.runAsync(() async {
        workspace = await Directory.systemTemp.createTemp(
          'codex-desk-agent-file-link-batch-',
        );
        controllerFile = File('${workspace.path}/app_controller.dart');
        specificationFile = File('${workspace.path}/本地工作树开发文档.md');
        await controllerFile.writeAsString('class Controller {}');
        await specificationFile.writeAsString('# Worktree');
      });
      addTearDown(() => workspace.delete(recursive: true));

      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = workspace.path
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-file-link-batch';
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/started',
          params: {
            'threadId': 'thread-file-link-batch',
            'turn': {'id': 'turn-file-link-batch'},
          },
        ),
      );
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'threadId': 'thread-file-link-batch',
            'turnId': 'turn-file-link-batch',
            'itemId': 'agent-file-link-batch',
            'delta':
                '- [app_controller.dart](${controllerFile.uri})\n'
                '- [spec](${specificationFile.uri})、'
                '[spec again](${specificationFile.uri})、'
                '[spec once more](${specificationFile.uri})',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      final streamingText = find.byKey(const Key('agent-streaming-text'));
      final streamingWidget = tester.widget<Text>(streamingText);
      expect(streamingWidget.data, isNot(contains(workspace.path)));
      expect(streamingWidget.data, contains('app_controller.dart'));
      final streamingRect = tester.getRect(streamingText);
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'threadId': 'thread-file-link-batch',
            'turnId': 'turn-file-link-batch',
            'item': {'id': 'agent-file-link-batch', 'type': 'agentMessage'},
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('agent-markdown-selection')), findsNothing);
      expect(tester.getRect(streamingText), streamingRect);

      final markdown = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'AgentMarkdown',
      );
      final markdownState = tester.state(markdown) as dynamic;
      await tester.runAsync(
        () => markdownState.resolveLocalLinksForTesting() as Future<void>,
      );
      await tester.pump();
      await tester.pump();

      expect(markdownState.resolvedLocalLinkCountForTesting, 2);
      expect(find.byKey(const Key('agent-streaming-text')), findsNothing);
      expect(find.byKey(const Key('agent-markdown-selection')), findsOneWidget);
      expect(find.text('app_controller.dart'), findsOneWidget);
      expect(find.text('本地工作树开发文档.md'), findsNWidgets(3));
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(4));
      final completedRect = tester.getRect(
        find.byKey(const Key('agent-markdown-selection')),
      );
      expect(completedRect.top, closeTo(streamingRect.top, 0.5));
      expect(completedRect.height, greaterThan(streamingRect.height));

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keeps streaming link destinations out of text layout before they close',
    (tester) async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-partial-file-link';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'itemId': 'partial-file-link',
            'delta': '查看 [codex_workspace.dart](/Volumes/External HD/Code/',
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump(const Duration(milliseconds: 60));

      final streamingText = find.byKey(const Key('agent-streaming-text'));
      final firstText = tester.widget<Text>(streamingText);
      expect(firstText.data, '查看 ');
      final firstRect = tester.getRect(streamingText);

      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {
            'itemId': 'partial-file-link',
            'delta': 'ChatGPT/lib/src/presentation/codex_workspace.dart:13643)',
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        tester.widget<Text>(streamingText).data,
        '查看 codex_workspace.dart',
      );
      expect(tester.getRect(streamingText), firstRect);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'preserves Markdown-like literals while streaming code and escapes',
    (tester) async {
      const literal =
          '行内 `[x](/tmp/code.dart)`\n```md\n[y](/tmp/fence.dart)\n```\n'
          r'转义 \[z](/tmp/literal.dart)';
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-streaming-code-link';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {'itemId': 'streaming-code-link', 'delta': literal},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        tester.widget<Text>(find.byKey(const Key('agent-streaming-text'))).data,
        literal,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keeps mismatched code spans and tilde fences out of link projection',
    (tester) async {
      const source =
          '`[inside](/tmp/code.dart)``[still](/tmp/still.dart)`\n'
          '~~~md\n[fenced](/tmp/fence.dart)\n~~~\n'
          '[outside](/tmp/outside.dart)';
      const projected =
          '`[inside](/tmp/code.dart)``[still](/tmp/still.dart)`\n'
          '~~~md\n[fenced](/tmp/fence.dart)\n~~~\n'
          'outside.dart';
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.running
        ..activeThreadId = 'thread-streaming-code-delimiters';
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/agentMessage/delta',
          params: {'itemId': 'streaming-code-delimiters', 'delta': source},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        tester.widget<Text>(find.byKey(const Key('agent-streaming-text'))).data,
        projected,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'falls back from a malformed local link without blocking final Markdown',
    (tester) async {
      late Directory workspace;
      late File document;
      await tester.runAsync(() async {
        workspace = await Directory.systemTemp.createTemp(
          'codex-desk-malformed-file-link-',
        );
        document = File('${workspace.path}/guide.md');
        await document.writeAsString('# Guide');
      });
      addTearDown(() => workspace.delete(recursive: true));

      final hugeLine = List<String>.filled(200, '9').join();
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = workspace.path
        ..replaceTimelineEntriesForTesting([
          TimelineEntry(
            kind: TimelineKind.agent,
            title: 'Codex',
            detail: '[guide](${document.path}:$hugeLine)',
            createdAt: DateTime(2026, 1, 1),
          ),
        ]);
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await _resolveLastAgentMarkdownLinks(tester);
      await tester.pump();

      expect(find.byKey(const Key('agent-streaming-text')), findsNothing);
      expect(find.byKey(const Key('agent-markdown-selection')), findsOneWidget);
      expect(find.text('guide'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('revalidates a cached Markdown file before opening its preview', (
    tester,
  ) async {
    late Directory workspace;
    late Directory outside;
    late File document;
    late File outsideDocument;
    await tester.runAsync(() async {
      workspace = await Directory.systemTemp.createTemp(
        'codex-desk-markdown-revalidation-',
      );
      outside = await Directory.systemTemp.createTemp(
        'codex-desk-markdown-revalidation-outside-',
      );
      document = File('${workspace.path}/guide.md');
      outsideDocument = File('${outside.path}/secret.md');
      await document.writeAsString('# Safe');
      await outsideDocument.writeAsString('outside secret');
    });
    addTearDown(() async {
      await workspace.delete(recursive: true);
      await outside.delete(recursive: true);
    });

    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = workspace.path;
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'item/agentMessage/delta',
        params: {
          'itemId': 'revalidated-markdown-message',
          'delta': '[guide](${document.uri})',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await _resolveLastAgentMarkdownLinks(tester);
    final fileRow = find
        .ancestor(of: find.text('guide.md'), matching: find.byType(InkWell))
        .first;
    expect(fileRow, findsOneWidget);

    await tester.runAsync(() async {
      await document.delete();
      await Link(document.path).create(outsideDocument.path);
      tester.widget<InkWell>(fileRow).onTap!();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    expect(find.byKey(const Key('markdown-preview-dialog')), findsNothing);
    expect(find.text('无法打开此链接或项目内文件。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the timeline pinned when a file row resolves late', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(680, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Directory workspace;
    late File artifact;
    await tester.runAsync(() async {
      workspace = await Directory.systemTemp.createTemp(
        'codex-desk-file-row-scroll-',
      );
      artifact = File(
        '${workspace.path}/${'long-artifact-name-' * 7}release.zip',
      );
      await artifact.writeAsBytes(const [0]);
    });
    addTearDown(() => workspace.delete(recursive: true));

    final initialEntries = List<TimelineEntry>.generate(
      28,
      (index) => TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '历史消息 $index\n${'内容 ' * 12}',
        createdAt: DateTime(2026, 1, 1, 0, 0, index),
      ),
    );
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = workspace.path
      ..replaceTimelineEntriesForTesting(initialEntries);
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();

    controller.replaceTimelineEntriesForTesting([
      ...initialEntries,
      TimelineEntry(
        kind: TimelineKind.agent,
        title: 'Codex',
        detail: '${'收尾内容 ' * 6}[x](${artifact.uri})${' 后续' * 6}',
        createdAt: DateTime(2026, 1, 1, 0, 1),
      ),
    ]);
    await tester.pump();
    await tester.pumpAndSettle();

    final timeline = tester.widget<ListView>(
      find.descendant(
        of: find.byKey(
          ValueKey('conversation-timeline-${workspace.path}:draft'),
        ),
        matching: find.byType(ListView),
      ),
    );
    timeline.controller!.jumpTo(timeline.controller!.position.maxScrollExtent);
    await tester.pump();
    expect(timeline.controller!.position.extentAfter, lessThan(1));
    final previousMaximum = timeline.controller!.position.maxScrollExtent;
    final resolverState = await _resolveLastAgentMarkdownLinks(tester);
    await tester.pump();

    expect(
      timeline.controller!.position.maxScrollExtent,
      isNot(closeTo(previousMaximum, 0.1)),
    );
    expect(timeline.controller!.position.extentAfter, lessThan(1));

    await tester.runAsync(
      () => resolverState.resolveLocalLinksForTesting() as Future<void>,
    );
    final readingOffset = timeline.controller!.position.maxScrollExtent - 72;
    timeline.controller!.jumpTo(readingOffset);
    await tester.pump();
    expect(timeline.controller!.offset, closeTo(readingOffset, 0.1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'keeps the timeline pinned for a file row inside a Markdown table',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(680, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late Directory workspace;
      late File artifact;
      await tester.runAsync(() async {
        workspace = await Directory.systemTemp.createTemp(
          'codex-desk-table-file-row-scroll-',
        );
        artifact = File('${workspace.path}/table-artifact.zip');
        await artifact.writeAsBytes(const [0]);
      });
      addTearDown(() => workspace.delete(recursive: true));

      final initialEntries = List<TimelineEntry>.generate(
        48,
        (index) => TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '历史消息 $index',
          createdAt: DateTime(2026, 1, 1, 0, 0, index),
        ),
      );
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = workspace.path
        ..replaceTimelineEntriesForTesting(initialEntries);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(fontSize: 4, height: 1),
            ),
          ),
          home: CodexWorkspace(controller: controller),
        ),
      );
      await tester.pump();

      controller.replaceTimelineEntriesForTesting([
        ...initialEntries,
        TimelineEntry(
          kind: TimelineKind.agent,
          title: 'Codex',
          detail: '| 结果 |\n| --- |\n| [x](${artifact.uri}) |',
          createdAt: DateTime(2026, 1, 1, 0, 1),
        ),
      ]);
      await tester.pump();
      await tester.pumpAndSettle();

      final timeline = tester.widget<ListView>(
        find.descendant(
          of: find.byKey(
            ValueKey('conversation-timeline-${workspace.path}:draft'),
          ),
          matching: find.byType(ListView),
        ),
      );
      timeline.controller!.jumpTo(
        timeline.controller!.position.maxScrollExtent,
      );
      await tester.pump();
      final previousMaximum = timeline.controller!.position.maxScrollExtent;
      await _resolveLastAgentMarkdownLinks(tester);
      await tester.pump();

      expect(
        timeline.controller!.position.maxScrollExtent,
        isNot(closeTo(previousMaximum, 0.1)),
      );
      expect(timeline.controller!.position.extentAfter, lessThan(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('opens only project-local Markdown file links', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'codex-desk-markdown-link-',
    );
    final document = File('${workspace.path}/technical-plan.md');
    await document.writeAsString('# Technical plan');
    final outside = await Directory.systemTemp.createTemp(
      'codex-desk-markdown-link-outside-',
    );
    final outsideDocument = File('${outside.path}/secret.md');
    await outsideDocument.writeAsString('# Outside');
    final indirectDocument = Link('${workspace.path}/indirect.md');
    await indirectDocument.create(outsideDocument.path);
    addTearDown(() async {
      await workspace.delete(recursive: true);
      await outside.delete(recursive: true);
    });

    Uri? opened;
    final didOpen = await openAgentMarkdownLink(
      href: 'technical-plan.md',
      workspacePath: workspace.path,
      launch: (uri) async {
        opened = uri;
        return true;
      },
    );

    expect(didOpen, isTrue);
    expect(opened, Uri.file(await document.resolveSymbolicLinks()));

    final didOpenOutside = await openAgentMarkdownLink(
      href: outsideDocument.uri.toString(),
      workspacePath: workspace.path,
      launch: (_) async => fail('must not open files outside the workspace'),
    );

    expect(didOpenOutside, isFalse);

    final didOpenIndirect = await openAgentMarkdownLink(
      href: 'indirect.md',
      workspacePath: workspace.path,
      launch: (_) async => fail('must not follow a link outside the workspace'),
    );

    expect(didOpenIndirect, isFalse);
  });

  test(
    'opens Codex Markdown file links with line and column suffixes',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'codex-desk-markdown-location-link-',
      );
      final document = File('${workspace.path}/technical plan.md');
      await document.writeAsString('# Technical plan');
      addTearDown(() => workspace.delete(recursive: true));

      final opened = <Uri>[];
      Future<bool> launch(Uri uri) async {
        opened.add(uri);
        return true;
      }

      expect(
        await openAgentMarkdownLink(
          href: 'technical%20plan.md',
          workspacePath: workspace.path,
          launch: launch,
        ),
        isTrue,
      );
      expect(
        opened.removeLast(),
        Uri.file(await document.resolveSymbolicLinks()),
      );

      expect(
        await openAgentMarkdownLink(
          href: 'technical%20plan.md:12',
          workspacePath: workspace.path,
          launch: launch,
        ),
        isTrue,
      );
      expect(
        opened.removeLast(),
        Uri.file(await document.resolveSymbolicLinks()),
      );

      expect(
        await openAgentMarkdownLink(
          href: '${document.path}:18',
          workspacePath: workspace.path,
          launch: launch,
        ),
        isTrue,
      );
      expect(
        opened.removeLast(),
        Uri.file(await document.resolveSymbolicLinks()),
      );

      expect(
        await openAgentMarkdownLink(
          href: '${document.uri}:12:4',
          workspacePath: workspace.path,
          launch: launch,
        ),
        isTrue,
      );
      expect(
        opened.removeLast(),
        Uri.file(await document.resolveSymbolicLinks()),
      );

      final locatedReference = await resolveWorkspaceFileReference(
        href: 'technical%20plan.md:27:6',
        workspacePath: workspace.path,
      );
      expect(locatedReference?.path, await document.resolveSymbolicLinks());
      expect(locatedReference?.line, 27);
      expect(locatedReference?.column, 6);

      final nestedDirectory = Directory('${workspace.path}/docs');
      await nestedDirectory.create();
      final nestedDocument = File('${nestedDirectory.path}/nested.md');
      await nestedDocument.writeAsString('# Nested');
      final relativeReference = await resolveWorkspaceFileReference(
        href: 'nested.md',
        workspacePath: workspace.path,
        relativeToDirectoryPath: nestedDirectory.path,
      );
      expect(
        relativeReference?.path,
        await nestedDocument.resolveSymbolicLinks(),
      );
    },
  );
}
