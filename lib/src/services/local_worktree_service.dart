import 'dart:async';
import 'dart:io';
import 'package:chatgpt/src/domain/local_worktree_record.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';

class LocalWorktreeService {
  LocalWorktreeService({RuntimeConfigurationStore? store})
    : _store = store ?? RuntimeConfigurationStore();

  final RuntimeConfigurationStore _store;
  final Map<String, Future<void>> _locks = {};

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
      final head = await _run(repository, ['rev-parse', selectedRef]);
      if (head.exitCode != 0) throw StateError('无法确定仓库当前提交。');
      final currentHead = await _run(repository, const ['rev-parse', 'HEAD']);
      if (currentHead.exitCode != 0) throw StateError('无法确定仓库当前提交。');
      final add = await _run(repository, [
        'worktree',
        'add',
        '--detach',
        target.path,
        head.stdout.trim(),
      ]);
      if (add.exitCode != 0) throw StateError('创建工作树失败，请检查 Git 仓库状态后重试。');
      try {
        if (head.stdout.trim() == currentHead.stdout.trim()) {
          await _carryTrackedChanges(source: canonicalSource, target: target);
        }
        await _copyWorktreeIncludes(source: canonicalSource, target: target);
      } catch (error) {
        await _run(canonicalSource.path, [
          'worktree',
          'remove',
          '--force',
          target.path,
        ]);
        throw StateError('无法把当前本地改动带入工作树：$error');
      }
      final record = LocalWorktreeRecord(
        worktreeId: id,
        projectId: projectId,
        sourceRepository: canonicalSource.path,
        worktreePath: target.path,
        baseCommit: head.stdout.trim(),
        baseRef: selectedRef == 'HEAD' ? null : selectedRef,
        state: LocalWorktreeState.ready,
        createdAt: DateTime.now(),
      );
      try {
        final records = await _store.readWorktreeRecords();
        await _store.saveWorktreeRecords([...records, record]);
      } on Object {
        await _run(canonicalSource.path, [
          'worktree',
          'remove',
          '--force',
          target.path,
        ]);
        rethrow;
      }
      return record;
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
    final entries = await list(record.sourceRepository);
    final registered = entries.any((entry) => entry['path'] == worktree.path);
    if (!registered) {
      throw StateError('Git 未登记该工作树，请刷新工作树列表后重试。');
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
    final result = await _run(record.sourceRepository, [
      'worktree',
      'remove',
      if (force) '--force',
      worktree.path,
    ]);
    if (result.exitCode != 0) throw StateError('无法删除工作树，请确认其中没有需要保留的改动。');
    final records = await _store.readWorktreeRecords();
    await _store.saveWorktreeRecords(
      records.map(
        (item) => item.worktreeId == record.worktreeId
            ? item.copyWith(state: LocalWorktreeState.removed)
            : item,
      ),
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
    if (removed.isNotEmpty) {
      final updated = records.map(
        (record) => removed.contains(record.worktreeId)
            ? record.copyWith(state: LocalWorktreeState.removed)
            : record,
      );
      await _store.saveWorktreeRecords(updated);
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
    final restored = await create(
      repository: record.sourceRepository,
      rootPath: rootPath,
      projectId: record.projectId,
      worktreeId: record.worktreeId,
    );
    final records = await _store.readWorktreeRecords();
    await _store.saveWorktreeRecords(
      records.where((item) => item.worktreeId != record.worktreeId).followedBy([
        restored,
      ]),
    );
    return restored;
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
