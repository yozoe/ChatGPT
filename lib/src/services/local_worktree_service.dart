import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart' show Hmac, SecretKey;
import 'package:chatgpt/src/domain/local_worktree_record.dart';
import 'package:chatgpt/src/domain/worktree_snapshot.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:chatgpt/src/services/worktree_snapshot_store.dart';

class LocalWorktreeService {
  LocalWorktreeService({
    RuntimeConfigurationStore? store,
    WorktreeSnapshotStore? snapshotStore,
  }) : _store = store ?? RuntimeConfigurationStore(),
       _snapshotStore = snapshotStore ?? WorktreeSnapshotStore(store: store);

  final RuntimeConfigurationStore _store;
  final WorktreeSnapshotStore _snapshotStore;
  final Map<String, Future<void>> _locks = {};
  static Future<void> _ownershipKeyLock = Future<void>.value();

  Future<List<Map<String, String>>> list(String repository) async {
    final result = await _run(repository, const [
      'worktree',
      'list',
      '--porcelain',
    ]);
    if (result.exitCode != 0) throw StateError('无法读取 Git 工作树列表。');
    final entries = <Map<String, String>>[];
    Map<String, String>? current;
    for (final line in result.stdout.split('\n')) {
      if (line.startsWith('worktree ')) {
        if (current != null) entries.add(current);
        current = {'path': line.substring(9).trim()};
      } else if (current != null && line.startsWith('HEAD ')) {
        current['head'] = line.substring(5).trim();
      } else if (current != null && line.startsWith('branch ')) {
        current['branch'] = line.substring(7).trim();
      }
    }
    if (current != null) entries.add(current);
    return entries;
  }

  Future<LocalWorktreeRecord> create({
    required String repository,
    required String rootPath,
    required String projectId,
    String? worktreeId,
    String? baseRef,
    bool fetchBeforeCreate = false,
    String? baseCommitOverride,
    bool carryTrackedChanges = true,
  }) async {
    if (!Directory(rootPath).isAbsolute) {
      throw StateError('工作树根目录必须是绝对路径。');
    }
    final id = worktreeId ?? 'wt-${DateTime.now().microsecondsSinceEpoch}';
    final root = Directory(rootPath);
    await root.create(recursive: true);
    return _withRepositoryLock(repository, () async {
      final canonicalRoot = await _canonicalDirectory(root);
      final canonicalSource = await _canonicalDirectory(Directory(repository));
      final commonDirectory = await _gitCommonDirectory(canonicalSource.path);
      if (_isWithin(canonicalSource, canonicalRoot)) {
        throw StateError('工作树根目录不能位于源仓库内。');
      }
      final target = Directory(
        '${canonicalRoot.path}${Platform.pathSeparator}$id',
      );
      if (!_isWithin(canonicalRoot, target) || await target.exists()) {
        throw StateError('目标工作树已存在或不在允许的根目录内。');
      }
      if (fetchBeforeCreate) {
        final fetch = await _run(repository, const ['fetch', '--prune']);
        if (fetch.exitCode != 0) throw StateError('获取远端更新失败，请检查网络后重试。');
      }
      final selectedRef = baseRef?.trim().isNotEmpty == true
          ? baseRef!.trim()
          : 'HEAD';
      final head = await _run(repository, [
        'rev-parse',
        baseCommitOverride ?? selectedRef,
      ]);
      if (head.exitCode != 0) throw StateError('无法确定仓库当前提交。');
      final currentHead = carryTrackedChanges
          ? await _run(repository, const ['rev-parse', 'HEAD'])
          : null;
      if (currentHead != null && currentHead.exitCode != 0) {
        throw StateError('无法确定仓库当前提交。');
      }
      final record = LocalWorktreeRecord(
        worktreeId: id,
        projectId: projectId,
        sourceRepository: canonicalSource.path,
        worktreePath: target.path,
        baseCommit: head.stdout.trim(),
        baseRef: selectedRef == 'HEAD' ? null : selectedRef,
        gitCommonDirectory: commonDirectory,
        ownershipNonce: _newNonce(),
        state: LocalWorktreeState.ready,
        createdAt: DateTime.now(),
      );
      final signedRecord = record.copyWith(
        ownershipMac: await _ownershipMac(record),
      );
      await _upsertRecord(
        signedRecord.copyWith(state: LocalWorktreeState.creating),
      );
      try {
        final add = await _run(repository, [
          'worktree',
          'add',
          '--detach',
          target.path,
          head.stdout.trim(),
        ]);
        if (add.exitCode != 0) {
          throw StateError('创建工作树失败，请检查 Git 仓库状态后重试。');
        }
        if (carryTrackedChanges &&
            head.stdout.trim() == currentHead?.stdout.trim()) {
          await _carryTrackedChanges(source: canonicalSource, target: target);
        }
        await _copyWorktreeIncludes(source: canonicalSource, target: target);
        await _upsertRecord(signedRecord);
      } on Object {
        await _run(canonicalSource.path, [
          'worktree',
          'remove',
          '--force',
          target.path,
        ]);
        await _removeRecord(id);
        rethrow;
      }
      return signedRecord;
    });
  }

  Future<void> remove({
    required LocalWorktreeRecord record,
    required String rootPath,
    bool force = false,
  }) async {
    final root = await _canonicalDirectory(Directory(rootPath));
    final worktree = await _canonicalDirectory(Directory(record.worktreePath));
    if (!_isWithin(root, worktree)) {
      throw StateError('工作树路径不在受管理的根目录内。');
    }
    final reconciliation = await reconcile(record: record, rootPath: rootPath);
    if (reconciliation != LocalWorktreeState.ready &&
        reconciliation != LocalWorktreeState.completed) {
      throw StateError('工作树所有权或 Git 登记不一致，已标记为 foreign，拒绝删除。');
    }
    if (!force) {
      final status = await _run(worktree.path, const [
        'status',
        '--porcelain',
        '--untracked-files=all',
      ]);
      if (status.exitCode != 0) throw StateError('无法检查工作树状态，请刷新后重试。');
      if (status.stdout.trim().isNotEmpty) {
        throw StateError('工作树包含未提交改动，请先处理改动后再删除。');
      }
    }
    final snapshot = await _snapshotStore.capture(record: record);
    final snapshotReference = await _snapshotStore.save(
      rootPath: root.path,
      snapshot: snapshot,
    );
    final snapshotRecord = record.copyWith(
      snapshotId: snapshotReference.snapshotId,
      snapshotDigest: snapshotReference.digest,
    );
    final signedSnapshotRecord = snapshotRecord.copyWith(
      ownershipMac: await _ownershipMac(snapshotRecord),
    );
    final result = await _run(record.sourceRepository, [
      'worktree',
      'remove',
      if (force) '--force',
      worktree.path,
    ]);
    if (result.exitCode != 0) {
      await _snapshotStore.delete(
        rootPath: root.path,
        snapshotId: snapshotReference.snapshotId,
      );
      throw StateError('无法删除工作树，请确认其中没有需要保留的改动。');
    }
    final records = await _store.readWorktreeRecords();
    await _store.saveWorktreeRecords(
      records.map(
        (item) => item.worktreeId == record.worktreeId
            ? signedSnapshotRecord.copyWith(state: LocalWorktreeState.removed)
            : item,
      ),
    );
  }

  /// Reconciles a persisted record with canonical paths and Git's authoritative
  /// worktree list. A mismatch is foreign; a missing directory is missing.
  Future<LocalWorktreeState> reconcile({
    required LocalWorktreeRecord record,
    required String rootPath,
  }) async {
    Directory worktree;
    Directory source;
    Directory root;
    try {
      root = await _canonicalDirectory(Directory(rootPath));
      source = await _canonicalDirectory(Directory(record.sourceRepository));
      if (!await Directory(record.worktreePath).exists()) {
        await _saveState(record, LocalWorktreeState.missing);
        return LocalWorktreeState.missing;
      }
      worktree = await _canonicalDirectory(Directory(record.worktreePath));
    } on FileSystemException {
      await _saveState(record, LocalWorktreeState.missing);
      return LocalWorktreeState.missing;
    }
    if (!_isWithin(root, worktree) || worktree.path == source.path) {
      await _saveState(record, LocalWorktreeState.foreign);
      return LocalWorktreeState.foreign;
    }
    final common = await _gitCommonDirectory(source.path);
    if (record.gitCommonDirectory != null &&
        record.gitCommonDirectory != common) {
      await _saveState(record, LocalWorktreeState.foreign);
      return LocalWorktreeState.foreign;
    }
    if (record.ownershipNonce == null && record.ownershipMac == null) {
      final upgraded = record.copyWith(
        gitCommonDirectory: common,
        ownershipNonce: _newNonce(),
        ownershipMac: null,
      );
      await _saveRecord(
        upgraded.copyWith(ownershipMac: await _ownershipMac(upgraded)),
      );
    } else if (record.ownershipNonce == null || record.ownershipMac == null) {
      await _saveState(record, LocalWorktreeState.foreign);
      return LocalWorktreeState.foreign;
    } else if (record.ownershipMac != await _ownershipMac(record)) {
      await _saveState(record, LocalWorktreeState.foreign);
      return LocalWorktreeState.foreign;
    }
    final entries = await list(source.path);
    final registered = entries.any((entry) => entry['path'] == worktree.path);
    if (registered) return record.state;
    await _saveState(record, LocalWorktreeState.foreign);
    return LocalWorktreeState.foreign;
  }

  /// Resolves a provisional creation left behind by an interrupted process.
  /// A registered or partially present path is never promoted to ready because
  /// initialization may have stopped before tracked changes and include files
  /// were verified. Such paths remain visible as foreign for manual review.
  Future<LocalWorktreeState> recoverCreating({
    required LocalWorktreeRecord record,
  }) async {
    if (record.state != LocalWorktreeState.creating) {
      throw StateError('只有 creating 状态的工作树可以恢复创建事务。');
    }
    try {
      final path = Directory(record.worktreePath);
      if (!await path.exists()) {
        await _saveState(record, LocalWorktreeState.failed);
        return LocalWorktreeState.failed;
      }
      // A present path is conservatively foreign even when Git no longer
      // lists it: it may contain a partially copied include or patch.
      await _saveState(record, LocalWorktreeState.foreign);
      return LocalWorktreeState.foreign;
    } on FileSystemException {
      await _saveState(record, LocalWorktreeState.failed);
      return LocalWorktreeState.failed;
    } on Object {
      await _saveState(record, LocalWorktreeState.foreign);
      return LocalWorktreeState.foreign;
    }
  }

  Future<void> _saveState(
    LocalWorktreeRecord record,
    LocalWorktreeState state,
  ) async {
    if (record.state == state) return;
    final records = await _store.readWorktreeRecords();
    await _store.saveWorktreeRecords(
      records.map(
        (item) => item.worktreeId == record.worktreeId
            ? item.copyWith(state: state)
            : item,
      ),
    );
  }

  Future<void> _saveRecord(LocalWorktreeRecord record) async {
    final records = await _store.readWorktreeRecords();
    await _store.saveWorktreeRecords(
      records.map(
        (item) => item.worktreeId == record.worktreeId ? record : item,
      ),
    );
  }

  Future<void> _upsertRecord(LocalWorktreeRecord record) async {
    final records = await _store.readWorktreeRecords();
    final exists = records.any((item) => item.worktreeId == record.worktreeId);
    await _store.saveWorktreeRecords(
      exists
          ? records.map(
              (item) => item.worktreeId == record.worktreeId ? record : item,
            )
          : [...records, record],
    );
  }

  Future<void> _removeRecord(String worktreeId) async {
    final records = await _store.readWorktreeRecords();
    await _store.saveWorktreeRecords(
      records.where((item) => item.worktreeId != worktreeId),
    );
  }

  Future<List<String>> cleanup({
    required String rootPath,
    required int retentionLimit,
    required Iterable<LocalWorktreeRecord> records,
  }) async {
    if (retentionLimit < 1) return const [];
    final candidates =
        records
            .where(
              (record) =>
                  record.state == LocalWorktreeState.completed &&
                  record.threadId != null,
            )
            .toList()
          ..sort(
            (a, b) => (a.lastUsedAt ?? a.createdAt).compareTo(
              b.lastUsedAt ?? b.createdAt,
            ),
          );
    final removeCount = candidates.length - retentionLimit;
    if (removeCount <= 0) return const [];
    final removed = <String>[];
    for (final record in candidates.take(removeCount)) {
      try {
        await remove(record: record, rootPath: rootPath);
        removed.add(record.worktreeId);
      } on Object {
        // A dirty, running, missing, or externally changed worktree is kept.
      }
    }
    return removed;
  }

  Future<LocalWorktreeRecord> restore({
    required LocalWorktreeRecord record,
    required String rootPath,
  }) async {
    if (record.state != LocalWorktreeState.removed) {
      throw StateError('只有已清理的工作树可以恢复。');
    }
    final snapshotId = record.snapshotId;
    final snapshotDigest = record.snapshotDigest;
    final snapshot = snapshotId != null && snapshotDigest != null
        ? await _snapshotStore.read(
            rootPath: rootPath,
            snapshotId: snapshotId,
            digest: snapshotDigest,
          )
        : null;
    final restored = await create(
      repository: record.sourceRepository,
      rootPath: rootPath,
      projectId: record.projectId,
      worktreeId: record.worktreeId,
      baseRef: record.baseRef,
      baseCommitOverride: record.baseCommit,
      carryTrackedChanges: false,
    );
    if (snapshot != null && snapshotId != null) {
      try {
        await _applySnapshot(restored, snapshot);
      } catch (_) {
        await remove(record: restored, rootPath: rootPath, force: true);
        rethrow;
      }
      await _snapshotStore.delete(rootPath: rootPath, snapshotId: snapshotId);
    }
    final records = await _store.readWorktreeRecords();
    await _store.saveWorktreeRecords(
      records.where((item) => item.worktreeId != record.worktreeId).followedBy([
        restored,
      ]),
    );
    return restored;
  }

  Future<void> _applySnapshot(
    LocalWorktreeRecord record,
    WorktreeSnapshot snapshot,
  ) async {
    if (snapshot.trackedPatch.trim().isNotEmpty) {
      final patchFile = File(
        '${Directory(record.worktreePath).parent.path}${Platform.pathSeparator}.codex-desk-restore-${DateTime.now().microsecondsSinceEpoch}.patch',
      );
      try {
        await patchFile.writeAsString(snapshot.trackedPatch, flush: true);
        final applied = await _run(record.worktreePath, [
          'apply',
          '--binary',
          patchFile.path,
        ]);
        if (applied.exitCode != 0) {
          throw StateError('工作树保护快照的 tracked 改动无法恢复。');
        }
      } finally {
        if (await patchFile.exists()) await patchFile.delete();
      }
    }
    final root = Directory(record.worktreePath);
    for (final entry in snapshot.files.entries) {
      final entity = _safeChild(root, entry.key);
      if (entity == null) throw StateError('快照包含越界路径：${entry.key}');
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw StateError('恢复目标包含符号链接：${entry.key}');
      }
      final file = File(entity.path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(base64Decode(entry.value), flush: true);
    }
  }

  Future<T> _withRepositoryLock<T>(
    String repository,
    Future<T> Function() action,
  ) async {
    final previous = _locks[repository] ?? Future<void>.value();
    final completer = Completer<void>();
    _locks[repository] = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_locks[repository], completer.future)) {
        _locks.remove(repository);
      }
    }
  }

  Future<Directory> _canonicalDirectory(Directory directory) async {
    return Directory(await directory.resolveSymbolicLinks());
  }

  bool _isWithin(Directory root, Directory candidate) {
    final base = root.absolute.path.endsWith(Platform.pathSeparator)
        ? root.absolute.path
        : '${root.absolute.path}${Platform.pathSeparator}';
    return candidate.absolute.path == root.absolute.path ||
        candidate.absolute.path.startsWith(base);
  }

  Future<ProcessResult> _run(String cwd, List<String> args) =>
      Process.run('git', args, workingDirectory: cwd);

  Future<String> _gitCommonDirectory(String repository) async {
    final result = await _run(repository, const [
      'rev-parse',
      '--git-common-dir',
    ]);
    if (result.exitCode != 0) {
      throw StateError('无法确定 Git common directory。');
    }
    final value = result.stdout.toString().trim();
    final directory = Directory(
      value.startsWith('/')
          ? value
          : '${Directory(repository).path}${Platform.pathSeparator}$value',
    );
    return (await _canonicalDirectory(directory)).path;
  }

  String _newNonce() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<String> _ownershipMac(LocalWorktreeRecord record) async {
    final key = await _readOrCreateOwnershipKey();
    final snapshotPart =
        record.snapshotId == null && record.snapshotDigest == null
        ? ''
        : '|${record.snapshotId}|${record.snapshotDigest}';
    final payload = utf8.encode(
      'v1|${record.worktreeId}|${record.projectId}|${record.sourceRepository}|'
      '${record.worktreePath}|${record.gitCommonDirectory}|${record.ownershipNonce}'
      '$snapshotPart',
    );
    final mac = await Hmac.sha256().calculateMac(
      payload,
      secretKey: SecretKey(utf8.encode(key)),
    );
    return base64UrlEncode(mac.bytes);
  }

  Future<String> _readOrCreateOwnershipKey() async {
    final previous = _ownershipKeyLock;
    final completer = Completer<void>();
    _ownershipKeyLock = completer.future;
    try {
      await previous;
      final stored = await _store.readWorktreeOwnershipKey();
      if (stored != null && stored.isNotEmpty) return stored;
      final generated = _newNonce();
      await _store.saveWorktreeOwnershipKey(generated);
      return generated;
    } finally {
      completer.complete();
    }
  }

  Future<void> _carryTrackedChanges({
    required Directory source,
    required Directory target,
  }) async {
    final diff = await _run(source.path, const ['diff', '--binary', 'HEAD']);
    if (diff.exitCode != 0) throw StateError('无法读取源仓库的本地改动。');
    final patch = diff.stdout.toString();
    if (patch.trim().isEmpty) return;
    final patchFile = File(
      '${target.parent.path}${Platform.pathSeparator}.codex-desk-${DateTime.now().microsecondsSinceEpoch}.patch',
    );
    try {
      await patchFile.writeAsString(patch, flush: true);
      final applied = await _run(target.path, [
        'apply',
        '--binary',
        patchFile.path,
      ]);
      if (applied.exitCode != 0) {
        throw StateError('源仓库的已跟踪改动无法应用到工作树。');
      }
    } finally {
      if (await patchFile.exists()) await patchFile.delete();
    }
  }

  Future<void> _copyWorktreeIncludes({
    required Directory source,
    required Directory target,
  }) async {
    final paths = <String>{};
    final includeFile = File(
      '${source.path}${Platform.pathSeparator}.worktreeinclude',
    );
    if (await includeFile.exists()) {
      for (final line in await includeFile.readAsLines()) {
        final value = line.trim();
        if (value.isEmpty || value.startsWith('#') || value.startsWith('/')) {
          continue;
        }
        paths.add(value.replaceAll('\\', '/'));
      }
    }
    final override = File(
      '${source.path}${Platform.pathSeparator}AGENTS.override.md',
    );
    if (await override.exists()) paths.add('AGENTS.override.md');
    for (final relative in paths) {
      final sourceEntity = _safeChild(source, relative);
      final targetEntity = _safeChild(target, relative);
      if (sourceEntity == null || targetEntity == null) {
        throw StateError('工作树包含越界的忽略文件路径：$relative');
      }
      final type = await FileSystemEntity.type(sourceEntity.path);
      if (type == FileSystemEntityType.notFound) continue;
      if (type == FileSystemEntityType.file) {
        await File(targetEntity.path).parent.create(recursive: true);
        await File(sourceEntity.path).copy(targetEntity.path);
      } else if (type == FileSystemEntityType.directory) {
        await _copyDirectory(
          Directory(sourceEntity.path),
          Directory(targetEntity.path),
        );
      }
    }
  }

  FileSystemEntity? _safeChild(Directory root, String relative) {
    final candidate = File('${root.path}${Platform.pathSeparator}$relative');
    final normalizedRoot = root.absolute.path.endsWith(Platform.pathSeparator)
        ? root.absolute.path
        : '${root.absolute.path}${Platform.pathSeparator}';
    final normalizedCandidate = candidate.absolute.path;
    if (normalizedCandidate == root.absolute.path ||
        !normalizedCandidate.startsWith(normalizedRoot) ||
        relative.split('/').contains('..')) {
      return null;
    }
    return candidate;
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      final destination = '${target.path}${Platform.pathSeparator}$name';
      if (entity is File) {
        await entity.copy(destination);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destination));
      }
    }
  }
}
