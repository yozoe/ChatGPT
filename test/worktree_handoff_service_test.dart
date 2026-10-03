import 'dart:io';

import 'package:chatgpt/src/services/codex_keychain_storage.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:chatgpt/src/services/worktree_handoff_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'moves only changes after generation zero and increments the checkpoint',
    () async {
      final root = await Directory.systemTemp.createTemp('worktree-handoff-');
      addTearDown(() => root.delete(recursive: true));
      final local = await Directory('${root.path}/local').create();
      final worktree = await Directory('${root.path}/worktree').create();
      await File('${local.path}/shared.txt').writeAsString('base');
      await File('${worktree.path}/shared.txt').writeAsString('base');
      final service = WorktreeHandoffService(
        store: RuntimeConfigurationStore(
          storage: CodexKeychainStorage(developmentDirectory: root),
        ),
      );
      await service.initialize(
        threadId: 'thread-1',
        worktreeId: 'wt-1',
        localPath: local.path,
        worktreePath: worktree.path,
      );
      await File('${local.path}/shared.txt').writeAsString('local change');
      final checkpoint = await service.handoff(
        threadId: 'thread-1',
        direction: 'localToWorktree',
        expectedGeneration: 0,
      );

      expect(checkpoint.generation, 1);
      expect(
        await File('${worktree.path}/shared.txt').readAsString(),
        'local change',
      );
    },
  );

  test('rejects overlapping edits before writing the target', () async {
    final root = await Directory.systemTemp.createTemp(
      'worktree-handoff-conflict-',
    );
    addTearDown(() => root.delete(recursive: true));
    final local = await Directory('${root.path}/local').create();
    final worktree = await Directory('${root.path}/worktree').create();
    await File('${local.path}/shared.txt').writeAsString('base');
    await File('${worktree.path}/shared.txt').writeAsString('base');
    final service = WorktreeHandoffService(
      store: RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      ),
    );
    await service.initialize(
      threadId: 'thread-1',
      worktreeId: 'wt-1',
      localPath: local.path,
      worktreePath: worktree.path,
    );
    await File('${local.path}/shared.txt').writeAsString('local change');
    await File('${worktree.path}/shared.txt').writeAsString('worktree change');

    await expectLater(
      service.handoff(threadId: 'thread-1', direction: 'localToWorktree'),
      throwsA(isA<StateError>()),
    );
    expect(
      await File('${worktree.path}/shared.txt').readAsString(),
      'worktree change',
    );
  });
}
