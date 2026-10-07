import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'widget_test_fakes.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/conversation_attachment_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _FakeRuntimeConfigurationStore = FakeRuntimeConfigurationStore;
typedef _FakeCodexAppServer = FakeCodexAppServer;

void main() {
  testWidgets('adds a locally rendered sketch as a temporary image', (
    tester,
  ) async {
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('composer-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('draw-menu-item')));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const Key('sketch-canvas'));
    final start = tester.getTopLeft(canvas) + const Offset(24, 24);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(80, 40));
    await gesture.up();
    await tester.pump();
    final attach = tester.widget<FilledButton>(
      find.byKey(const Key('sketch-attach-button')),
    );
    expect(attach.onPressed, isNotNull);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('sketch-attach-button')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sketch-canvas-dialog')), findsNothing);
    expect(find.byKey(const Key('composer-image-thumbnail')), findsOneWidget);
    final send = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!;
    server.startTurnError = StateError('sketch turn rejected');
    await tester.runAsync(() async {
      send();
      for (
        var attempt = 0;
        attempt < 20 && controller.lastError == null;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();
    expect(find.byKey(const Key('composer-image-thumbnail')), findsOneWidget);
    expect(controller.lastError, contains('sketch turn rejected'));

    server.startTurnError = null;
    final retrySend = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!;
    await tester.runAsync(() async {
      retrySend();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(server.startedTurnAdditionalInput, hasLength(1));
    expect(server.startedTurnAdditionalInput.single['type'], 'localImage');
    expect(server.startedTurnAdditionalInput.single['path'], isA<String>());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('highlights the composer and deduplicates dropped files', (
    tester,
  ) async {
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    var dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragEntered?.call(
      DropEventDetails(
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('composer-drop-overlay')), findsOneWidget);
    expect(find.text('松开即可添加文件'), findsOneWidget);

    dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [
          DropItemFile('/tmp/design.png'),
          DropItemFile('/tmp/design.png'),
          DropItemDirectory('/tmp/reference-folder', const []),
        ],
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('composer-drop-overlay')), findsNothing);
    expect(
      find.byKey(const Key('composer-attachment-/tmp/design.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-attachment-/tmp/reference-folder')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pastes copied files and folders as composer attachments', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readFileItems');
      return [
        {'path': '/tmp/copied.png', 'isDirectory': false},
        {'path': '/tmp/copied-folder', 'isDirectory': true},
        {'path': '/tmp/copied.png', 'isDirectory': false},
        {'path': '/tmp/trailing-space ', 'isDirectory': false},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('composer-field')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const Key('composer-attachment-/tmp/copied.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-attachment-/tmp/copied-folder')),
      findsOneWidget,
    );
    expect(find.text('copied.png'), findsOneWidget);
    expect(find.text('copied-folder'), findsOneWidget);
    expect(
      find.byKey(const Key('composer-attachment-/tmp/trailing-space ')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('retains pasted screenshots for the timeline', (tester) async {
    const channel = MethodChannel('codex_desk/clipboard');
    const imagePath = '/tmp/CodexDeskClipboard/clipboard-image-42.png';
    final temporaryImage = File(imagePath);
    temporaryImage.parent.createSync(recursive: true);
    addTearDown(() {
      if (temporaryImage.existsSync()) temporaryImage.deleteSync();
    });
    final imageProvider = FileImage(File(imagePath));
    // Creating a raster image is real async engine work. Running it through
    // WidgetTester avoids leaving Picture.toImage suspended in FakeAsync.
    final testImage =
        await tester.runAsync(
          () => createTestImage(width: 1024, height: 1024, cache: false),
        ) ??
        (throw StateError('Unable to create the test image.'));
    temporaryImage.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9WQAAAABJRU5ErkJggg==',
      ),
    );
    PaintingBinding.instance.imageCache.putIfAbsent(
      imageProvider,
      () => OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: testImage)),
      ),
    );
    addTearDown(() {
      PaintingBinding.instance.imageCache.evict(imageProvider);
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var deleteCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readFileItems':
          return [
            {'path': imagePath, 'isDirectory': false, 'isTemporary': true},
          ];
        case 'deleteTemporaryItem':
          expect(call.arguments, imagePath);
          deleteCalls++;
          if (temporaryImage.existsSync()) temporaryImage.deleteSync();
          return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'new-thread'},
      ];
    final persistedImages =
        await tester.runAsync(
          () => Directory.systemTemp.createTemp('codex-desk-timeline-images-'),
        ) ??
        (throw StateError('Unable to create the test attachment directory.'));
    addTearDown(() => persistedImages.delete(recursive: true));
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
      conversationAttachmentStore: ConversationAttachmentStore(
        directory: persistedImages,
      ),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('composer-field')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final screenshotChip = find.byKey(Key('composer-attachment-$imagePath'));
    expect(screenshotChip, findsOneWidget);
    expect(
      find.descendant(
        of: screenshotChip,
        matching: find.byKey(const Key('composer-image-thumbnail')),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('composer-image-thumbnail')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const Key('composer-image-preview-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('composer-image-preview')), findsOneWidget);
    expect(
      find.byKey(const Key('composer-image-interactive-viewer')),
      findsOneWidget,
    );
    final viewerFinder = find.byKey(
      const Key('composer-image-interactive-viewer'),
    );
    final viewportSize = tester.getSize(viewerFinder);
    final fittedScale = math.min(
      1.0,
      math.min(viewportSize.width / 1024, viewportSize.height / 1024),
    );
    final fittedPercent = (fittedScale * 100).round();
    expect(find.byKey(const Key('composer-image-open-button')), findsOneWidget);
    expect(find.byKey(const Key('composer-image-save-button')), findsOneWidget);
    expect(
      find.byKey(const Key('composer-image-close-button')),
      findsOneWidget,
    );
    expect(find.text('$fittedPercent%'), findsOneWidget);
    expect(fittedPercent, lessThan(100));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('composer-image-zoom-in')));
    await tester.pump();
    expect(find.text('${(fittedScale * 125).round()}%'), findsOneWidget);
    await tester.drag(viewerFinder, const Offset(-60, -40));
    await tester.pump();
    final transformationController = tester
        .widget<InteractiveViewer>(viewerFinder)
        .transformationController!;
    final viewportCenter = viewportSize.center(Offset.zero);
    final sceneCenterBeforeZoom = transformationController.toScene(
      viewportCenter,
    );
    await tester.tap(find.byKey(const Key('composer-image-zoom-in')));
    await tester.pump();
    final sceneCenterAfterZoom = transformationController.toScene(
      viewportCenter,
    );
    expect(sceneCenterAfterZoom.dx, closeTo(sceneCenterBeforeZoom.dx, 0.01));
    expect(sceneCenterAfterZoom.dy, closeTo(sceneCenterBeforeZoom.dy, 0.01));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.text('$fittedPercent%'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const Key('composer-image-preview-dialog')),
      findsNothing,
    );
    final send = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!;
    // Image promotion copies a file through dart:io, so invoke the async
    // callback in WidgetTester.runAsync instead of the fake test clock.
    await tester.runAsync(() async {
      send();
      for (
        var attempt = 0;
        attempt < 100 &&
            !controller.entries.any((entry) => entry.imagePaths.isNotEmpty);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final durablePath = controller.entries
        .where((entry) => entry.imagePaths.isNotEmpty)
        .single
        .imagePaths
        .single;
    final durableImageProvider = FileImage(File(durablePath));
    PaintingBinding.instance.imageCache.putIfAbsent(
      durableImageProvider,
      () => OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: testImage)),
      ),
    );
    addTearDown(() {
      PaintingBinding.instance.imageCache.evict(durableImageProvider);
    });
    expect(server.startedTurnAdditionalInput, [
      {'type': 'localImage', 'path': durablePath},
    ]);
    expect(deleteCalls, 1);
    expect(temporaryImage.existsSync(), isFalse);
    expect(await tester.runAsync(() => File(durablePath).exists()), isTrue);
    expect(find.byKey(ValueKey('timeline-image-$durablePath')), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('timeline-image-preview-$durablePath')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const Key('composer-image-preview-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('composer-image-close-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const Key('composer-image-preview-dialog')),
      findsNothing,
    );

    // Navigating away disposes the Composer while the controller and turn
    // remain alive. The durable copied image must outlive that short-lived
    // widget even though its clipboard source was released after submission.
    await tester.tap(find.byKey(const Key('sidebar-scheduled-tasks-button')));
    await tester.pump();
    expect(find.byKey(const Key('composer-panel')), findsNothing);
    expect(deleteCalls, 1);
    expect(temporaryImage.existsSync(), isFalse);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(deleteCalls, 1);
    expect(temporaryImage.existsSync(), isFalse);

    // Creating a task removes the final timeline reference without trying to
    // release the already-released clipboard source again.
    controller.createThread();
    await tester.pump();
    expect(deleteCalls, 1);
    expect(temporaryImage.existsSync(), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(deleteCalls, 1);
    expect(temporaryImage.existsSync(), isFalse);
  });

  testWidgets('transfers an unsent screenshot when the controller changes', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    const imagePath = '/tmp/CodexDeskClipboard/controller-transfer-image.png';
    final temporaryImage = File(imagePath);
    temporaryImage.parent.createSync(recursive: true);
    temporaryImage.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9WQAAAABJRU5ErkJggg==',
      ),
    );
    addTearDown(() {
      if (temporaryImage.existsSync()) temporaryImage.deleteSync();
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var deleteCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readFileItems':
          return [
            {'path': imagePath, 'isDirectory': false, 'isTemporary': true},
          ];
        case 'deleteTemporaryItem':
          expect(call.arguments, imagePath);
          deleteCalls++;
          if (temporaryImage.existsSync()) temporaryImage.deleteSync();
          return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final firstController = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    final secondController = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: firstController)),
    );
    await tester.tap(find.byKey(const Key('composer-field')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.byKey(Key('composer-attachment-$imagePath')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: secondController)),
    );
    await tester.pump();
    expect(deleteCalls, 0);
    expect(temporaryImage.existsSync(), isTrue);
    expect(find.byKey(Key('composer-attachment-$imagePath')), findsOneWidget);

    final firstEntryCount = firstController.entries.length;
    await tester.tap(find.byKey(const Key('sidebar-new-chat-button')));
    await tester.pump();
    expect(firstController.entries, hasLength(firstEntryCount));
    expect(secondController.entries, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(deleteCalls, 1);
    expect(temporaryImage.existsSync(), isFalse);
  });

  testWidgets('falls back to normal text paste when no file is copied', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': '粘贴文本'};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.enterText(find.byKey(const Key('composer-field')), '已有内容：');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(find.text('已有内容：粘贴文本'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-pasted-text-1')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('collapses multiline paste and can restore it at the selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(560, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('codex_desk/clipboard');
    final pastedText = List.generate(
      9,
      (index) => index == 0 ? '2026-09-06T05:00:00Z' : '第 $index 行内容',
    ).join('\n');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': pastedText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final fieldFinder = find.byKey(const Key('composer-field'));
    await tester.enterText(fieldFinder, '前缀待替换后缀');
    tester.widget<TextField>(fieldFinder).controller!.selection =
        const TextSelection(baseOffset: 2, extentOffset: 5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(fieldFinder).controller!.text, '前缀后缀');
    expect(
      find.byKey(const ValueKey('composer-pasted-text-1')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('composer-pasted-text-scroll')))
          .height,
      lessThan(60),
    );
    expect(
      find.text(
        '2026-09-06T05:00:00Z 第 1 行内容 第 2 行内容 第 3 行内容 第 4 行内容 第 5 行内容 第 6 行内容 第 7 行内容 第 8 行内容',
      ),
      findsOneWidget,
    );
    expect(find.text('在文本框中显示 ›'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('composer-pasted-text-remove-1')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('composer-pasted-text-1')), findsNothing);
    expect(tester.widget<TextField>(fieldFinder).controller!.text, '前缀后缀');

    await tester.tap(fieldFinder);
    tester.widget<TextField>(fieldFinder).controller!.selection =
        const TextSelection.collapsed(offset: 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('composer-pasted-text-2')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('composer-pasted-text-show-2')));
    await tester.pump();

    expect(
      tester.widget<TextField>(fieldFinder).controller!.text,
      '前缀$pastedText后缀',
    );
    expect(find.byKey(const ValueKey('composer-pasted-text-2')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sends collapsed text intact and clears its composer card', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final pastedText = List.filled(90, '需要保留的长文本片段').join(' ');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': pastedText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'new-thread'},
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final fieldFinder = find.byKey(const Key('composer-field'));
    await tester.enterText(fieldFinder, '请总结这段文本');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('composer-pasted-text-1')),
      findsOneWidget,
    );

    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(server.startedTurnPrompt, '请总结这段文本\n\n$pastedText');
    expect(tester.widget<TextField>(fieldFinder).controller!.text, isEmpty);
    expect(find.byKey(const ValueKey('composer-pasted-text-1')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('retains collapsed text when task start fails', (tester) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final pastedText = List.filled(90, '失败后仍需保留的文本').join(' ');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': pastedText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'new-thread'},
      ]
      ..startTurnError = StateError('turn rejected');
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final fieldFinder = find.byKey(const Key('composer-field'));
    await tester.enterText(fieldFinder, '失败后保留指令');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<TextField>(fieldFinder).controller!.text, '失败后保留指令');
    expect(
      find.byKey(const ValueKey('composer-pasted-text-1')),
      findsOneWidget,
    );
    expect(server.startedTurnPrompt, '失败后保留指令\n\n$pastedText');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('queues collapsed text while an active turn is running', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final pastedText = List.filled(90, '运行中追加的长文本').join(' ');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': pastedText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final server = _FakeCodexAppServer();
    final controller = CodexController(server: server)
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.running
      ..activeThreadId = 'thread-1'
      ..activeTurnId = 'turn-1';
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final fieldFinder = find.byKey(const Key('composer-field'));
    await tester.enterText(fieldFinder, '请调整当前方向');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.pendingTurnSteer?.displayText, '请调整当前方向\n\n$pastedText');
    expect(find.byKey(const ValueKey('composer-pasted-text-1')), findsNothing);
    await tester.tap(find.byKey(const Key('adjust-direction-button')));
    await tester.pump();
    expect(server.steeredTurnPrompt, '请调整当前方向\n\n$pastedText');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps many pasted text cards inside a scrolling region', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(560, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('codex_desk/clipboard');
    final pastedText = List.filled(90, '窄窗口中的多卡片文本').join(' ');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': pastedText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = CodexController(server: _FakeCodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('composer-field')));
    for (var index = 0; index < 12; index++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }
    await tester.pump();

    final scrollRegion = find.byKey(const Key('composer-pasted-text-scroll'));
    expect(scrollRegion, findsOneWidget);
    expect(tester.getSize(scrollRegion).height, lessThanOrEqualTo(110));
    final scrollable = find.descendant(
      of: scrollRegion,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0),
    );
    expect(
      find.byKey(const ValueKey('composer-pasted-text-12')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('composer-field')), findsOneWidget);
    expect(find.byTooltip('发送任务'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sends image-suffixed directories as path context', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return [
        {'path': '/tmp/reference.png', 'isDirectory': true},
        {'path': '/tmp/design.png', 'isDirectory': false},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final server = _FakeCodexAppServer()
      ..listResponse = [
        {'id': 'new-thread'},
      ];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.enterText(find.byKey(const Key('composer-field')), '检查附件');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.canSend, isTrue);
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(server.startedTurnPrompt, contains('附加路径：/tmp/reference.png'));
    expect(server.startedTurnAdditionalInput, [
      {
        'type': 'mention',
        'name': 'reference.png',
        'path': '/tmp/reference.png',
      },
      {'type': 'localImage', 'path': '/tmp/design.png'},
    ]);
    expect(
      find.byKey(const Key('composer-attachment-/tmp/reference.png')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps composer text and attachments when task start fails', (
    tester,
  ) async {
    const channel = MethodChannel('codex_desk/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => [
        {'path': '/tmp/retry.txt', 'isDirectory': false},
      ],
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = CodexController(
      server: _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'new-thread'},
        ]
        ..startTurnError = StateError('turn rejected'),
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.enterText(find.byKey(const Key('composer-field')), '保留这个输入');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.canSend, isTrue);
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final field = tester.widget<TextField>(
      find.byKey(const Key('composer-field')),
    );
    expect(field.controller?.text, '保留这个输入');
    expect(
      find.byKey(const Key('composer-attachment-/tmp/retry.txt')),
      findsOneWidget,
    );
    expect(controller.lastError, contains('turn rejected'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('releases dropped security scope after the turn completes', (
    tester,
  ) async {
    const dropChannel = MethodChannel('desktop_drop');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var startCalls = 0;
    var stopCalls = 0;
    messenger.setMockMethodCallHandler(dropChannel, (call) async {
      switch (call.method) {
        case 'startAccessingSecurityScopedResource':
          startCalls++;
          return true;
        case 'stopAccessingSecurityScopedResource':
          stopCalls++;
          return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(dropChannel, null));
    final controller = CodexController(
      server: _FakeCodexAppServer()
        ..listResponse = [
          {'id': 'new-thread'},
        ],
      runtimeConfigurationStore: _FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [
          DropItemFile(
            '/tmp/scoped.txt',
            extraAppleBookmark: Uint8List.fromList([1, 2, 3]),
          ),
        ],
        localPosition: const Offset(40, 40),
        globalPosition: const Offset(40, 40),
      ),
    );
    await tester.pumpAndSettle();
    expect(startCalls, 1);

    expect(controller.canSend, isTrue);
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送任务',
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(stopCalls, 0);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/completed',
        params: {
          'turn': {'status': 'completed'},
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(stopCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });
}
