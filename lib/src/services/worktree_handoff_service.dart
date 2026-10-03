import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/domain/worktree_handoff_checkpoint.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:cryptography/cryptography.dart';

/// Performs conservative, incremental two-sided Worktree Handoff.
///
/// Snapshots are stored as base64 file contents so conflict detection never
/// guesses from the repository's current HEAD. The service refuses overlapping
/// edits and only commits a new generation after the target is fully written.
class WorktreeHandoffService {
  WorktreeHandoffService({RuntimeConfigurationStore? store})
    : _store = store ?? RuntimeConfigurationStore();

  final RuntimeConfigurationStore _store;

  Future<WorktreeHandoffCheckpoint> initialize({
    required String threadId,
    required String worktreeId,
    required String localPath,
    required String worktreePath,
  }) async {
    final checkpoint = WorktreeHandoffCheckpoint(
      threadId: threadId,
      worktreeId: worktreeId,
      localPath: localPath,
      worktreePath: worktreePath,
      generation: 0,
      localSnapshot: await _snapshot(localPath),
      worktreeSnapshot: await _snapshot(worktreePath),
    );
    await _save(checkpoint);
    return checkpoint;
  }

  Future<WorktreeHandoffCheckpoint> handoff({
    required String threadId,
    required String direction,
    int? expectedGeneration,
  }) async {
    final checkpoints = await _store.readWorktreeHandoffCheckpoints();
    final checkpoint = checkpoints
        .where((item) => item.threadId == threadId)
        .firstOrNull;
    if (checkpoint == null) {
      throw StateError('该任务尚未建立 Worktree Handoff generation 0。');
    }
    if (expectedGeneration != null &&
        checkpoint.generation != expectedGeneration) {
      throw StateError('Worktree Handoff 状态已变化，请刷新后重试。');
    }
    final sourceIsLocal = direction == 'localToWorktree';
    if (!sourceIsLocal && direction != 'worktreeToLocal') {
      throw ArgumentError.value(direction, 'direction');
    }
    final sourcePath = sourceIsLocal
        ? checkpoint.localPath
        : checkpoint.worktreePath;
    final targetPath = sourceIsLocal
        ? checkpoint.worktreePath
        : checkpoint.localPath;
    final sourceBaseline = sourceIsLocal
        ? checkpoint.localSnapshot
        : checkpoint.worktreeSnapshot;
    final targetBaseline = sourceIsLocal
        ? checkpoint.worktreeSnapshot
        : checkpoint.localSnapshot;
    final sourceCurrent = await _snapshot(sourcePath);
    final targetCurrent = await _snapshot(targetPath);
    final sourceChanges = _changedPaths(sourceCurrent, sourceBaseline);
    final targetChanges = _changedPaths(targetCurrent, targetBaseline);
    final conflicts = sourceChanges.intersection(targetChanges).where((path) {
      return sourceCurrent[path] != targetCurrent[path];
    }).toList()..sort();
    if (conflicts.isNotEmpty) {
      throw StateError('Worktree Handoff 存在冲突文件：${conflicts.join('、')}');
    }
    await _applyChanges(
      targetPath,
      sourceCurrent,
      sourceChanges.difference(targetChanges),
    );
    final next = WorktreeHandoffCheckpoint(
      threadId: checkpoint.threadId,
      worktreeId: checkpoint.worktreeId,
      localPath: checkpoint.localPath,
      worktreePath: checkpoint.worktreePath,
      generation: checkpoint.generation + 1,
      localSnapshot: await _snapshot(checkpoint.localPath),
      worktreeSnapshot: await _snapshot(checkpoint.worktreePath),
    );
    await _save(next);
    return next;
  }

  Future<Map<String, String>> _snapshot(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) throw StateError('Handoff 目录不存在：$rootPath');
    final result = <String, String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = _relative(root.path, entity.path);
      if (_excluded(relative)) continue;
      final bytes = await entity.readAsBytes();
      final digest = await Sha256().hash(bytes);
      result[relative] =
          '${base64Encode(bytes)}:${base64UrlEncode(digest.bytes)}';
    }
    return result;
  }

  Future<void> _applyChanges(
    String targetPath,
    Map<String, String> source,
    Set<String> changed,
  ) async {
    final root = Directory(targetPath);
    for (final relative in changed) {
      final target = File('${root.path}${Platform.pathSeparator}$relative');
      final encoded = source[relative];
      if (encoded == null) {
        if (await target.exists()) await target.delete();
        continue;
      }
      final separator = encoded.lastIndexOf(':');
      if (separator <= 0) throw StateError('Handoff 快照损坏：$relative');
      final bytes = base64Decode(encoded.substring(0, separator));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
    }
  }

  Set<String> _changedPaths(
    Map<String, String> current,
    Map<String, String> baseline,
  ) {
    final paths = {...current.keys, ...baseline.keys};
    return paths.where((path) => current[path] != baseline[path]).toSet();
  }

  Future<void> _save(WorktreeHandoffCheckpoint checkpoint) async {
    final checkpoints = await _store.readWorktreeHandoffCheckpoints();
    await _store.saveWorktreeHandoffCheckpoints([
      ...checkpoints.where((item) => item.threadId != checkpoint.threadId),
      checkpoint,
    ]);
  }

  String _relative(String root, String path) {
    final prefix = '$root${Platform.pathSeparator}';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  bool _excluded(String path) =>
      path == '.git' ||
      path.startsWith('.git${Platform.pathSeparator}') ||
      path.startsWith('.codex-worktree-metadata${Platform.pathSeparator}');
}
