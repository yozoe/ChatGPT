import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/conversation_attachment_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'delayed_conversation_attachment_store.dart';
import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rolls back earlier durable copies when a later image cannot be read',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-attachment-rollback-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/first.png');
      await source.writeAsBytes(const [137, 80, 78, 71]);
      final attachments = Directory('${root.path}/conversation-images');
      final store = ConversationAttachmentStore(directory: attachments);

      await expectLater(
        store.persist([source.path, '${root.path}/missing.png']),
        throwsA(isA<FileSystemException>()),
      );

      expect(await attachments.exists(), isTrue);
      expect(await attachments.list().isEmpty, isTrue);
    },
  );

  test(
    'rejects stale clipboard image paths before sending to App Server',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-stale-clipboard-',
      );
      addTearDown(() => root.delete(recursive: true));
      final controller =
          CodexController(
              server: FakeCodexAppServer(),
              conversationAttachmentStore: ConversationAttachmentStore(
                directory: Directory('${root.path}/conversation-images'),
              ),
            )
            ..workspacePath = root.path
            ..status = RuntimeStatus.ready;

      final sent = await controller.sendPrompt(
        '请检查旧截图',
        imagePaths: const [
          '/var/folders/nr/0prp0wxd57s33ld6bnlnw7rc0000gn/T/'
              'CodexDeskClipboard/clipboard-image-387.png',
        ],
        additionalInput: const [
          {
            'type': 'localImage',
            'path':
                '/var/folders/nr/0prp0wxd57s33ld6bnlnw7rc0000gn/T/'
                'CodexDeskClipboard/clipboard-image-387.png',
          },
        ],
      );

      expect(sent, isFalse);
      expect(
        controller.entries.any(
          (entry) =>
              entry.kind == TimelineKind.error &&
              entry.detail.contains('找不到待保存的图片'),
        ),
        isTrue,
      );
      controller.dispose();
    },
  );

  test(
    'keeps a temporary image alive while persistence is in flight',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-in-flight-attachment-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/clipboard-image.png');
      await source.writeAsBytes(const [137, 80, 78, 71]);
      const clipboardChannel = MethodChannel('codex_desk/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final sourceDeleted = Completer<void>();
      messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
        if (call.method != 'deleteTemporaryItem') return null;
        final path = call.arguments as String;
        final file = File(path);
        if (await file.exists()) await file.delete();
        if (!sourceDeleted.isCompleted) sourceDeleted.complete();
        return true;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(clipboardChannel, null),
      );
      final store = DelayedConversationAttachmentStore(
        directory: Directory('${root.path}/conversation-images'),
      );
      final server = FakeCodexAppServer();
      final runtime = FakeRuntimeConfigurationStore()..workspace = root.path;
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: runtime,
        conversationAttachmentStore: store,
      );
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.ready;
      controller.retainTemporaryAttachment(source.path);

      final send = controller.sendPrompt(
        '请检查图片',
        imagePaths: [source.path],
        additionalInput: [
          {'type': 'localImage', 'path': source.path},
        ],
      );
      await store.persistStarted.future;

      controller.releaseTemporaryAttachment(source.path);
      await Future<void>.delayed(Duration.zero);
      expect(await source.exists(), isTrue);

      store.continuePersist.complete();
      expect(await send, isTrue);
      final durablePath = server.startedTurnAdditionalInput.single['path'];
      expect(durablePath, isA<String>());
      expect(await File(durablePath as String).exists(), isTrue);
      await sourceDeleted.future;
      expect(await source.exists(), isFalse);
      controller.dispose();
    },
  );

  test(
    'removes a durable steer image when App Server rejects the direction',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-steer-attachment-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/clipboard-image.png');
      await source.writeAsBytes(const [137, 80, 78, 71]);
      final attachments = Directory('${root.path}/conversation-images');
      final server = FakeCodexAppServer()
        ..steerTurnError = StateError('turn rejected');
      final controller =
          CodexController(
              server: server,
              conversationAttachmentStore: ConversationAttachmentStore(
                directory: attachments,
              ),
            )
            ..workspacePath = root.path
            ..activeThreadId = 'thread-1'
            ..activeTurnId = 'turn-1'
            ..status = RuntimeStatus.running;
      controller.retainTemporaryAttachment(source.path);

      expect(
        await controller.steerCurrentTurn(
          '请重新检查图片',
          imagePaths: [source.path],
          additionalInput: [
            {'type': 'localImage', 'path': source.path},
          ],
        ),
        isFalse,
      );
      expect(await source.exists(), isTrue);
      expect(await attachments.list().isEmpty, isTrue);
      controller.dispose();
    },
  );

  test(
    'reuses a failed turn image instead of copying it again on retry',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-desk-retry-attachment-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/clipboard-image.png');
      await source.writeAsBytes(const [137, 80, 78, 71]);
      final attachments = Directory('${root.path}/conversation-images');
      final runtime = FakeRuntimeConfigurationStore()..workspace = root.path;
      final server = FakeCodexAppServer()
        ..startTurnError = StateError('runtime rejected turn')
        ..listResponse = [
          {
            'id': 'new-thread',
            'preview': '请检查图片',
            'createdAt': 1,
            'updatedAt': 1,
            'status': 'active',
          },
        ];
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: runtime,
        conversationAttachmentStore: ConversationAttachmentStore(
          directory: attachments,
        ),
      );
      await controller.waitForInitialConfiguration();
      controller.status = RuntimeStatus.ready;
      controller.retainTemporaryAttachment(source.path);

      expect(
        await controller.sendPrompt(
          '请检查图片',
          imagePaths: [source.path],
          additionalInput: [
            {'type': 'localImage', 'path': source.path},
          ],
        ),
        isFalse,
      );
      final durablePath = controller.entries
          .where((entry) => entry.imagePaths.isNotEmpty)
          .single
          .imagePaths
          .single;
      expect(await attachments.list().length, 1);
      expect(controller.hasFailedTurnRetry, isTrue);

      server.startTurnError = null;
      expect(await controller.retryFailedTurn(), isTrue);
      expect(await attachments.list().length, 1);
      expect(server.startedTurnAdditionalInput, [
        {'type': 'localImage', 'path': durablePath},
      ]);
      controller.dispose();
    },
  );

  test('restores a sent clipboard image after a controller restart', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-persisted-image-',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = await Directory('${root.path}/workspace').create();
    final clipboardDirectory = await Directory(
      '${root.path}/CodexDeskClipboard',
    ).create();
    final source = File('${clipboardDirectory.path}/clipboard-image-1.png');
    await source.writeAsBytes(const [137, 80, 78, 71]);
    final attachments = Directory('${root.path}/conversation-images');
    final history = MemoryConversationHistoryStore();
    final runtime = FakeRuntimeConfigurationStore()..workspace = workspace.path;
    final server = FakeCodexAppServer();
    final firstController = CodexController(
      server: server,
      runtimeConfigurationStore: runtime,
      conversationHistoryStore: history,
      conversationAttachmentStore: ConversationAttachmentStore(
        directory: attachments,
      ),
    );
    await firstController.waitForInitialConfiguration();
    firstController.status = RuntimeStatus.ready;
    firstController.retainTemporaryAttachment(source.path);

    final sent = await firstController.sendPrompt(
      '请查看图片',
      imagePaths: [source.path],
      additionalInput: [
        {'type': 'localImage', 'path': source.path},
      ],
    );

    expect(sent, isTrue);
    final durablePath = firstController.entries
        .where((entry) => entry.imagePaths.isNotEmpty)
        .single
        .imagePaths
        .single;
    expect(durablePath, isNot(source.path));
    expect(await File(durablePath).readAsBytes(), [137, 80, 78, 71]);
    expect(server.startedTurnAdditionalInput, [
      {'type': 'localImage', 'path': durablePath},
    ]);
    expect(
      ConversationAttachmentStore.storesImageBytesEncryptedAtRest,
      isFalse,
    );
    await firstController.saveConversationHistoryForTesting();
    firstController.dispose();
    await source.delete();

    final restoredController = CodexController(
      server: FakeCodexAppServer(),
      runtimeConfigurationStore: runtime,
      conversationHistoryStore: history,
      conversationAttachmentStore: ConversationAttachmentStore(
        directory: attachments,
      ),
    );
    await restoredController.waitForInitialConfiguration();

    expect(
      restoredController.entries
          .where((entry) => entry.imagePaths.isNotEmpty)
          .single
          .imagePaths,
      [durablePath],
    );
    expect(await File(durablePath).exists(), isTrue);
    restoredController.dispose();
  });

  test('restores a sent image after reopening an inactive thread', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-desk-inactive-image-',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = await Directory('${root.path}/workspace').create();
    final clipboardDirectory = await Directory(
      '${root.path}/CodexDeskClipboard',
    ).create();
    final source = File('${clipboardDirectory.path}/clipboard-image-2.png');
    await source.writeAsBytes(const [137, 80, 78, 71]);
    final attachments = Directory('${root.path}/conversation-images');
    final history = MemoryConversationHistoryStore();
    final runtime = FakeRuntimeConfigurationStore()..workspace = workspace.path;
    final firstServer = FakeCodexAppServer()
      ..startThreadResponseIds.add('thread-a');
    final firstController = CodexController(
      server: firstServer,
      runtimeConfigurationStore: runtime,
      conversationHistoryStore: history,
      conversationAttachmentStore: ConversationAttachmentStore(
        directory: attachments,
      ),
    );
    await firstController.waitForInitialConfiguration();
    firstController.status = RuntimeStatus.ready;
    firstController.retainTemporaryAttachment(source.path);

    expect(
      await firstController.sendPrompt(
        '线程 A 的截图',
        imagePaths: [source.path],
        additionalInput: [
          {'type': 'localImage', 'path': source.path},
        ],
      ),
      isTrue,
    );
    final durablePath = firstController.entries
        .singleWhere((entry) => entry.imagePaths.isNotEmpty)
        .imagePaths
        .single;
    firstController
      ..threads = const [
        CodexThread(
          id: 'thread-a',
          preview: '线程 A 的截图',
          createdAt: 1,
          updatedAt: 1,
        ),
        CodexThread(
          id: 'thread-b',
          preview: '另一个任务',
          createdAt: 2,
          updatedAt: 2,
        ),
      ]
      ..activeThreadId = 'thread-b';
    firstController.replaceTimelineEntriesForTesting(const []);
    await firstController.saveConversationHistoryForTesting();
    firstController.dispose();

    final secondServer = FakeCodexAppServer()
      ..resumeResult = {
        'thread': {
          'turns': [
            {
              'id': 'turn-a',
              'items': [
                {
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': '线程 A 的截图'},
                  ],
                },
              ],
            },
          ],
        },
      };
    final restoredController = CodexController(
      server: secondServer,
      runtimeConfigurationStore: runtime,
      conversationHistoryStore: history,
      conversationAttachmentStore: ConversationAttachmentStore(
        directory: attachments,
      ),
    );
    await restoredController.waitForInitialConfiguration();
    restoredController.status = RuntimeStatus.ready;

    await restoredController.resumeThread(
      restoredController.threads.firstWhere(
        (thread) => thread.id == 'thread-a',
      ),
    );

    expect(
      restoredController.entries
          .singleWhere((entry) => entry.detail == '线程 A 的截图')
          .imagePaths,
      [durablePath],
    );
    restoredController.dispose();
  });
}
