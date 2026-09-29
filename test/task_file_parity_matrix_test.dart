import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

Future<void> _completeFileTurn(
  CodexController controller,
  String prompt, {
  required List<JsonMap> changes,
  String? diff,
  String threadId = 'new-thread',
}) async {
  expect(
    await controller.sendPrompt(prompt),
    isTrue,
    reason: controller.lastError,
  );
  final turnId = 'turn-${prompt.hashCode}';
  controller.handleServerEventForTesting(
    ServerEvent(
      method: 'turn/started',
      params: {
        'threadId': threadId,
        'turn': {'id': turnId},
      },
    ),
  );
  if (changes.isNotEmpty) {
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'item/completed',
        params: {
          'threadId': threadId,
          'item': {'type': 'fileChange', 'changes': changes},
        },
      ),
    );
  }
  if (diff != null) {
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'turn/diff/updated',
        params: {'threadId': threadId, 'diff': diff},
      ),
    );
  }
  controller.handleServerEventForTesting(
    ServerEvent(
      method: 'turn/completed',
      params: {
        'threadId': threadId,
        'turn': {'id': turnId, 'status': 'completed'},
      },
    ),
  );
}

String _diff(String path, String oldValue, String newValue) =>
    'diff --git a/$path b/$path\n'
    '--- a/$path\n'
    '+++ b/$path\n'
    '@@ -1 +1 @@\n'
    '-$oldValue\n'
    '+$newValue';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'keeps the parity matrix scopes separate across four file turns',
    () async {
      final server = FakeCodexAppServer();
      final git = FakeGitProjectService();
      final controller = CodexController(server: server, gitProjectService: git)
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      addTearDown(controller.dispose);

      final firstDiff = _diff('lib/old.dart', 'before', 'first');
      final thirdDiff = _diff('lib/old.dart', 'first', 'third');
      final fourthDiff = _diff('lib/new.dart', 'missing', 'fourth');

      await _completeFileTurn(
        controller,
        'first turn',
        changes: [
          {'path': 'lib/old.dart', 'kind': 'modified', 'diff': firstDiff},
        ],
        diff: firstDiff,
      );
      expect(controller.fileChanges.map((change) => change.path), [
        'lib/old.dart',
      ]);
      expect(controller.turnFileChanges.map((change) => change.path), [
        'lib/old.dart',
      ]);

      await _completeFileTurn(
        controller,
        'second turn only asks a question',
        changes: const [],
      );
      expect(controller.fileChanges.map((change) => change.path), [
        'lib/old.dart',
      ]);
      expect(controller.turnFileChanges, isEmpty);
      expect(controller.turnDiff, isNull);

      await _completeFileTurn(
        controller,
        'third turn updates the old file',
        changes: [
          {'path': 'lib/old.dart', 'kind': 'modified', 'diff': thirdDiff},
        ],
        diff: thirdDiff,
      );
      expect(controller.fileChanges.map((change) => change.path), [
        'lib/old.dart',
      ]);
      expect(controller.turnFileChanges.single.path, 'lib/old.dart');

      await _completeFileTurn(
        controller,
        'fourth turn creates a new file',
        changes: [
          {'path': 'lib/new.dart', 'kind': 'added', 'diff': fourthDiff},
        ],
        diff: fourthDiff,
      );
      expect(controller.fileChanges.map((change) => change.path), [
        'lib/old.dart',
        'lib/new.dart',
      ]);
      expect(controller.turnFileChanges.map((change) => change.path), [
        'lib/new.dart',
      ]);
      expect(controller.turnDiff, fourthDiff);
      expect(controller.canUndoFileChanges, isTrue);
      expect(await controller.undoFileChanges(), isTrue);
      expect(git.reversedDiff, fourthDiff);
      expect(controller.fileChanges.map((change) => change.path), [
        'lib/old.dart',
      ]);
    },
  );

  test(
    'preserves the matrix state when a thread is restored after a switch',
    () async {
      final history = MemoryConversationHistoryStore();
      final workspace = Directory.current;
      final runtimeConfigurationStore = FakeRuntimeConfigurationStore()
        ..workspace = workspace.path;
      final server = FakeCodexAppServer();
      final controller =
          CodexController(
              server: server,
              runtimeConfigurationStore: runtimeConfigurationStore,
              conversationHistoryStore: history,
            )
            ..workspacePath = workspace.path
            ..status = RuntimeStatus.ready;
      const diff =
          'diff --git a/lib/main.dart b/lib/main.dart\n'
          '--- a/lib/main.dart\n'
          '+++ b/lib/main.dart\n'
          '@@ -1 +1 @@\n'
          '-old\n'
          '+new';
      addTearDown(controller.dispose);

      await _completeFileTurn(
        controller,
        'change one file',
        changes: [
          {'path': 'lib/main.dart', 'kind': 'modified', 'diff': diff},
        ],
        diff: diff,
      );
      await controller.saveConversationHistoryForTesting();
      controller.createThread();
      expect(controller.fileChanges, isEmpty);

      final restored = CodexController(
        server: FakeCodexAppServer(),
        runtimeConfigurationStore: runtimeConfigurationStore,
        conversationHistoryStore: history,
      );
      addTearDown(restored.dispose);
      await restored.waitForInitialConfiguration();

      expect(restored.activeThreadId, 'new-thread');
      expect(restored.fileChanges.single.path, 'lib/main.dart');
      expect(restored.turnFileChanges.single.path, 'lib/main.dart');
      expect(restored.turnDiff, diff);
    },
  );

  test(
    'isolates task files when switching projects and restores the original project',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-task-file-workspace-switch-',
      );
      addTearDown(() => root.delete(recursive: true));
      final firstWorkspace = await Directory('${root.path}/first').create();
      final secondWorkspace = await Directory('${root.path}/second').create();
      final firstPath = await firstWorkspace.resolveSymbolicLinks();
      final secondPath = await secondWorkspace.resolveSymbolicLinks();
      final history = MemoryConversationHistoryStore();
      final server = FakeCodexAppServer()
        ..startThreadResponseIds.addAll(['first-thread', 'second-thread']);
      final controller = CodexController(
        server: server,
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        conversationHistoryStore: history,
      )..status = RuntimeStatus.ready;
      addTearDown(controller.dispose);
      await controller.waitForInitialConfiguration();

      await controller.selectWorkspace(
        firstPath,
        allowWhileRunning: true,
        pathAlreadyValidated: true,
      );
      final firstDiff = _diff('lib/first.dart', 'old', 'first');
      await _completeFileTurn(
        controller,
        'first project turn',
        changes: [
          {'path': 'lib/first.dart', 'kind': 'modified', 'diff': firstDiff},
        ],
        diff: firstDiff,
        threadId: 'first-thread',
      );
      await controller.saveConversationHistoryForTesting();

      await controller.selectWorkspace(
        secondPath,
        allowWhileRunning: true,
        pathAlreadyValidated: true,
      );
      expect(controller.workspacePath, secondPath);
      expect(controller.fileChanges, isEmpty);
      expect(controller.turnFileChanges, isEmpty);
      expect(controller.turnDiff, isNull);

      final secondDiff = _diff('lib/second.dart', 'old', 'second');
      await _completeFileTurn(
        controller,
        'second project turn',
        changes: [
          {'path': 'lib/second.dart', 'kind': 'modified', 'diff': secondDiff},
        ],
        diff: secondDiff,
        threadId: 'second-thread',
      );
      await controller.saveConversationHistoryForTesting();

      await controller.selectWorkspace(
        firstPath,
        allowWhileRunning: true,
        pathAlreadyValidated: true,
      );
      expect(controller.workspacePath, firstPath);
      expect(controller.activeThreadId, 'first-thread');
      expect(controller.fileChanges.single.path, 'lib/first.dart');
      expect(controller.turnFileChanges.single.path, 'lib/first.dart');
      expect(controller.turnDiff, firstDiff);
      expect(
        controller.fileChanges.any(
          (change) => change.path == 'lib/second.dart',
        ),
        isFalse,
      );
    },
  );

  test(
    'keeps undo unavailable for metadata-only and binary-only matrix rows',
    () {
      final metadataController =
          CodexController(
              server: CodexAppServer(),
              gitProjectService: FakeGitProjectService(),
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;
      addTearDown(metadataController.dispose);
      metadataController.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {
              'type': 'fileChange',
              'changes': [
                {'path': 'lib/main.dart', 'kind': 'modified'},
              ],
            },
          },
        ),
      );
      metadataController.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {
            'diff':
                'diff --git a/lib/main.dart b/lib/main.dart\n'
                'index 123..456 100644',
          },
        ),
      );

      final binaryController =
          CodexController(
              server: CodexAppServer(),
              gitProjectService: FakeGitProjectService(),
            )
            ..workspacePath = '/workspace'
            ..status = RuntimeStatus.ready;
      addTearDown(binaryController.dispose);
      binaryController.handleServerEventForTesting(
        const ServerEvent(
          method: 'item/completed',
          params: {
            'item': {
              'type': 'fileChange',
              'changes': [
                {'path': 'assets/logo.png', 'kind': 'modified'},
              ],
            },
          },
        ),
      );
      binaryController.handleServerEventForTesting(
        const ServerEvent(
          method: 'turn/diff/updated',
          params: {
            'diff':
                'diff --git a/assets/logo.png b/assets/logo.png\n'
                'Binary files a/assets/logo.png and b/assets/logo.png differ',
          },
        ),
      );

      expect(metadataController.canUndoFileChanges, isFalse);
      expect(binaryController.canUndoFileChanges, isFalse);
    },
  );
}
