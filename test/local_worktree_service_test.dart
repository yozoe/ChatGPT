import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/services/local_worktree_service.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:chatgpt/src/services/codex_keychain_storage.dart';
import 'package:chatgpt/src/domain/local_worktree_record.dart';

Future<void> runGit(Directory directory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
}

void main() {
  test(
    'creates a detached worktree and carries tracked and included files',
    () async {
      final root = await Directory.systemTemp.createTemp('codex-worktree-');
      addTearDown(() => root.delete(recursive: true));
      final repository = await Directory('${root.path}/repo').create();
      final worktrees = await Directory('${root.path}/worktrees').create();
      await runGit(repository, ['init', '-q']);
      await runGit(repository, ['config', 'user.email', 'test@example.com']);
      await runGit(repository, ['config', 'user.name', 'Codex Test']);
      await File('${repository.path}/tracked.txt').writeAsString('before\n');
      await runGit(repository, ['add', '.']);
      await runGit(repository, ['commit', '-qm', 'initial']);
      await File('${repository.path}/tracked.txt').writeAsString('after\n');
      await File('${repository.path}/ignored.secret').writeAsString('secret');
      await File(
        '${repository.path}/.worktreeinclude',
      ).writeAsString('ignored.secret\n');

      final service = LocalWorktreeService(
        store: RuntimeConfigurationStore(
          storage: CodexKeychainStorage(developmentDirectory: root),
        ),
      );
      final record = await service.create(
        repository: repository.path,
        rootPath: worktrees.path,
        projectId: 'project-1',
      );

      expect(record.state, LocalWorktreeState.ready);
      expect(
        await File('${record.worktreePath}/tracked.txt').readAsString(),
        'after\n',
      );
      expect(
        await File('${record.worktreePath}/ignored.secret').readAsString(),
        'secret',
      );
      final metadata = File(
        '${worktrees.path}/.codex-worktree-metadata/${record.worktreeId}.json',
      );
      expect(metadata.existsSync(), isTrue);
      expect(
        jsonDecode(await metadata.readAsString())['worktreePath'],
        record.worktreePath,
      );
      final porcelain = await service.list(repository.path);
      expect(
        porcelain.any((entry) => entry['path'] == record.worktreePath),
        isTrue,
      );
    },
  );

  test('creates a detached worktree from the selected base branch', () async {
    final root = await Directory.systemTemp.createTemp('codex-worktree-ref-');
    addTearDown(() => root.delete(recursive: true));
    final repository = await Directory('${root.path}/repo').create();
    final worktrees = await Directory('${root.path}/worktrees').create();
    await runGit(repository, ['init', '-q']);
    await runGit(repository, ['config', 'user.email', 'test@example.com']);
    await runGit(repository, ['config', 'user.name', 'Codex Test']);
    await File('${repository.path}/base.txt').writeAsString('base\n');
    await runGit(repository, ['add', '.']);
    await runGit(repository, ['commit', '-qm', 'initial']);
    await runGit(repository, ['branch', 'feature']);

    final service = LocalWorktreeService(
      store: RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      ),
    );
    final record = await service.create(
      repository: repository.path,
      rootPath: worktrees.path,
      projectId: 'project-1',
      baseRef: 'feature',
    );

    expect(record.baseRef, 'feature');
    final head = await Process.run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: record.worktreePath);
    final feature = await Process.run('git', [
      'rev-parse',
      'feature',
    ], workingDirectory: repository.path);
    expect(head.stdout.toString().trim(), feature.stdout.toString().trim());
    final branch = await Process.run('git', [
      'branch',
      '--show-current',
    ], workingDirectory: record.worktreePath);
    expect(branch.stdout.toString().trim(), isEmpty);
  });

  test(
    'marks a record foreign when its Git common directory changes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-worktree-audit-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = await Directory('${root.path}/repo').create();
      final worktrees = await Directory('${root.path}/worktrees').create();
      await runGit(repository, ['init', '-q']);
      await runGit(repository, ['config', 'user.email', 'test@example.com']);
      await runGit(repository, ['config', 'user.name', 'Codex Test']);
      await File('${repository.path}/tracked.txt').writeAsString('ok\n');
      await runGit(repository, ['add', '.']);
      await runGit(repository, ['commit', '-qm', 'initial']);
      final service = LocalWorktreeService(
        store: RuntimeConfigurationStore(
          storage: CodexKeychainStorage(developmentDirectory: root),
        ),
      );
      final record = await service.create(
        repository: repository.path,
        rootPath: worktrees.path,
        projectId: 'project-1',
      );
      final foreign = LocalWorktreeRecord(
        worktreeId: record.worktreeId,
        projectId: record.projectId,
        sourceRepository: record.sourceRepository,
        worktreePath: record.worktreePath,
        baseCommit: record.baseCommit,
        baseRef: record.baseRef,
        gitCommonDirectory: '/different/.git',
        state: record.state,
        createdAt: record.createdAt,
      );
      expect(
        await service.reconcile(record: foreign, rootPath: worktrees.path),
        LocalWorktreeState.foreign,
      );
      await expectLater(
        service.remove(record: foreign, rootPath: worktrees.path),
        throwsStateError,
      );
      expect(Directory(record.worktreePath).existsSync(), isTrue);
    },
  );

  test('marks a record foreign when its ownership MAC is tampered', () async {
    final root = await Directory.systemTemp.createTemp('codex-worktree-mac-');
    addTearDown(() => root.delete(recursive: true));
    final repository = await Directory('${root.path}/repo').create();
    final worktrees = await Directory('${root.path}/worktrees').create();
    await runGit(repository, ['init', '-q']);
    await runGit(repository, ['config', 'user.email', 'test@example.com']);
    await runGit(repository, ['config', 'user.name', 'Codex Test']);
    await File('${repository.path}/tracked.txt').writeAsString('ok\n');
    await runGit(repository, ['add', '.']);
    await runGit(repository, ['commit', '-qm', 'initial']);
    final service = LocalWorktreeService(
      store: RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      ),
    );
    final record = await service.create(
      repository: repository.path,
      rootPath: worktrees.path,
      projectId: 'project-1',
    );
    expect(
      await service.reconcile(
        record: record.copyWith(ownershipMac: 'tampered'),
        rootPath: worktrees.path,
      ),
      LocalWorktreeState.foreign,
    );
  });

  test(
    'requires the external worktree manifest during reconciliation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-worktree-meta-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = await Directory('${root.path}/repo').create();
      final worktrees = await Directory('${root.path}/worktrees').create();
      await runGit(repository, ['init', '-q']);
      await runGit(repository, ['config', 'user.email', 'test@example.com']);
      await runGit(repository, ['config', 'user.name', 'Codex Test']);
      await File('${repository.path}/tracked.txt').writeAsString('ok\n');
      await runGit(repository, ['add', '.']);
      await runGit(repository, ['commit', '-qm', 'initial']);
      final service = LocalWorktreeService(
        store: RuntimeConfigurationStore(
          storage: CodexKeychainStorage(developmentDirectory: root),
        ),
      );
      final record = await service.create(
        repository: repository.path,
        rootPath: worktrees.path,
        projectId: 'project-1',
      );
      await File(
        '${worktrees.path}/.codex-worktree-metadata/${record.worktreeId}.json',
      ).delete();

      expect(
        await service.reconcile(record: record, rootPath: worktrees.path),
        LocalWorktreeState.foreign,
      );
      await expectLater(
        service.remove(record: record, rootPath: worktrees.path),
        throwsStateError,
      );
      expect(Directory(record.worktreePath).existsSync(), isTrue);
    },
  );

  test('does not promote an interrupted creating record to ready', () async {
    final root = await Directory.systemTemp.createTemp(
      'codex-worktree-recover-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = await Directory('${root.path}/repo').create();
    final worktrees = await Directory('${root.path}/worktrees').create();
    await runGit(repository, ['init', '-q']);
    await runGit(repository, ['config', 'user.email', 'test@example.com']);
    await runGit(repository, ['config', 'user.name', 'Codex Test']);
    await File('${repository.path}/tracked.txt').writeAsString('ok\n');
    await runGit(repository, ['add', '.']);
    await runGit(repository, ['commit', '-qm', 'initial']);
    final store = RuntimeConfigurationStore(
      storage: CodexKeychainStorage(developmentDirectory: root),
    );
    final service = LocalWorktreeService(store: store);
    final record = await service.create(
      repository: repository.path,
      rootPath: worktrees.path,
      projectId: 'project-1',
    );
    final provisional = record.copyWith(state: LocalWorktreeState.creating);
    await store.saveWorktreeRecords([provisional]);

    expect(
      await service.recoverCreating(record: provisional),
      LocalWorktreeState.foreign,
    );
    expect(
      (await store.readWorktreeRecords()).single.state,
      LocalWorktreeState.foreign,
    );
  });

  test(
    'restores from the recorded base commit instead of current HEAD',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-worktree-restore-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = await Directory('${root.path}/repo').create();
      final worktrees = await Directory('${root.path}/worktrees').create();
      await runGit(repository, ['init', '-q']);
      await runGit(repository, ['config', 'user.email', 'test@example.com']);
      await runGit(repository, ['config', 'user.name', 'Codex Test']);
      await File('${repository.path}/state.txt').writeAsString('base\n');
      await runGit(repository, ['add', '.']);
      await runGit(repository, ['commit', '-qm', 'base']);
      final store = RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      );
      final service = LocalWorktreeService(store: store);
      final record = await service.create(
        repository: repository.path,
        rootPath: worktrees.path,
        projectId: 'project-1',
      );
      await runGit(repository, ['checkout', '-qb', 'later']);
      await File('${repository.path}/state.txt').writeAsString('later\n');
      await runGit(repository, ['add', '.']);
      await runGit(repository, ['commit', '-qm', 'later']);
      await runGit(repository, ['checkout', '-q', 'later']);
      await store.saveWorktreeRecords([
        record.copyWith(state: LocalWorktreeState.removed),
      ]);
      await Process.run('git', [
        'worktree',
        'remove',
        '--force',
        record.worktreePath,
      ], workingDirectory: repository.path);

      final restored = await service.restore(
        record: record.copyWith(state: LocalWorktreeState.removed),
        rootPath: worktrees.path,
      );

      expect(
        await File('${restored.worktreePath}/state.txt').readAsString(),
        'base\n',
      );
      expect(restored.baseCommit, record.baseCommit);
    },
  );

  test(
    'captures an encrypted snapshot before forced removal and restores it',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'codex-worktree-snapshot-',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = await Directory('${root.path}/repo').create();
      final worktrees = await Directory('${root.path}/worktrees').create();
      await runGit(repository, ['init', '-q']);
      await runGit(repository, ['config', 'user.email', 'test@example.com']);
      await runGit(repository, ['config', 'user.name', 'Codex Test']);
      await File('${repository.path}/tracked.txt').writeAsString('base\n');
      await runGit(repository, ['add', '.']);
      await runGit(repository, ['commit', '-qm', 'base']);
      final store = RuntimeConfigurationStore(
        storage: CodexKeychainStorage(developmentDirectory: root),
      );
      final service = LocalWorktreeService(store: store);
      final record = await service.create(
        repository: repository.path,
        rootPath: worktrees.path,
        projectId: 'project-1',
      );
      await File(
        '${record.worktreePath}/tracked.txt',
      ).writeAsString('changed\n');
      await File(
        '${record.worktreePath}/untracked.bin',
      ).writeAsBytes([1, 2, 3]);

      await service.remove(
        record: record,
        rootPath: worktrees.path,
        force: true,
      );
      final removed = (await store.readWorktreeRecords()).single;
      expect(removed.state, LocalWorktreeState.removed);
      expect(removed.snapshotId, isNotNull);
      expect(removed.snapshotDigest, isNotNull);
      expect(
        File(
          '${worktrees.path}/.codex-worktree-metadata/${record.worktreeId}.json',
        ).existsSync(),
        isFalse,
      );
      final snapshotFile = File(
        '${worktrees.path}/.codex-snapshots/${removed.snapshotId}.json',
      );
      final encryptedSnapshot = await snapshotFile.readAsBytes();
      expect(utf8.decode(encryptedSnapshot), isNot(contains('changed')));
      await snapshotFile.writeAsBytes([...encryptedSnapshot, 0]);
      await expectLater(
        service.restore(record: removed, rootPath: worktrees.path),
        throwsStateError,
      );
      expect(Directory(removed.worktreePath).existsSync(), isFalse);
      await snapshotFile.writeAsBytes(encryptedSnapshot);

      final restored = await service.restore(
        record: removed,
        rootPath: worktrees.path,
      );

      expect(
        await File('${restored.worktreePath}/tracked.txt').readAsString(),
        'changed\n',
      );
      expect(
        await File('${restored.worktreePath}/untracked.bin').readAsBytes(),
        [1, 2, 3],
      );
      expect(await snapshotFile.exists(), isFalse);
    },
  );
}
