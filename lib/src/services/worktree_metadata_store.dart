import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/domain/local_worktree_record.dart';

/// 在托管工作树根目录之外保存可独立核对的所有权清单。
/// Stores an independently checkable ownership manifest outside the managed worktree.
class WorktreeMetadataStore {
  /// Writes one manifest with an atomic temporary-file replacement.
  ///
  /// The manifest is deliberately limited to non-secret identity and path
  /// fields. It complements the application record; it is not a Keychain or
  /// external trust authority.
  Future<void> write({
    required String rootPath,
    required LocalWorktreeRecord record,
  }) async {
    final file = await _manifestFile(
      rootPath: rootPath,
      worktreeId: record.worktreeId,
      createDirectory: true,
    );
    final temporary = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final payload = <String, Object?>{
      'version': 1,
      'worktreeId': record.worktreeId,
      'projectId': record.projectId,
      'sourceRepository': record.sourceRepository,
      'worktreePath': record.worktreePath,
      'baseCommit': record.baseCommit,
      if (record.isPermanent) 'isPermanent': true,
      if (record.baseRef != null) 'baseRef': record.baseRef,
      if (record.gitCommonDirectory != null)
        'gitCommonDirectory': record.gitCommonDirectory,
      if (record.ownershipNonce != null)
        'ownershipNonce': record.ownershipNonce,
      if (record.ownershipMac != null) 'ownershipMac': record.ownershipMac,
      'createdAt': record.createdAt.toIso8601String(),
    };
    try {
      await temporary.writeAsString(jsonEncode(payload), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Reads a manifest, returning null for a missing or malformed file.
  ///
  /// Malformed metadata is treated as absent so callers can conservatively
  /// classify the worktree as foreign instead of attempting repair.
  Future<Map<String, Object?>?> read({
    required String rootPath,
    required String worktreeId,
  }) async {
    try {
      final file = await _manifestFile(
        rootPath: rootPath,
        worktreeId: worktreeId,
        createDirectory: false,
      );
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Removes a known manifest without touching the Git worktree itself.
  /// Deletes one known manifest and never removes the Git worktree.
  Future<void> delete({
    required String rootPath,
    required String worktreeId,
  }) async {
    final file = await _manifestFile(
      rootPath: rootPath,
      worktreeId: worktreeId,
      createDirectory: false,
    );
    if (await file.exists()) await file.delete();
  }

  /// Returns the stable path used for a worktree's external manifest.
  /// Returns the stable path used by a worktree's external manifest.
  Future<String> path({
    required String rootPath,
    required String worktreeId,
  }) async => (await _manifestFile(
    rootPath: rootPath,
    worktreeId: worktreeId,
    createDirectory: false,
  )).path;

  Future<File> _manifestFile({
    required String rootPath,
    required String worktreeId,
    required bool createDirectory,
  }) async {
    if (worktreeId.isEmpty ||
        worktreeId == '.' ||
        worktreeId == '..' ||
        worktreeId.contains('/') ||
        worktreeId.contains('\\')) {
      throw ArgumentError.value(worktreeId, 'worktreeId');
    }
    final root = Directory(rootPath);
    if (createDirectory) await root.create(recursive: true);
    final metadata = Directory('${root.path}/.codex-worktree-metadata');
    if (createDirectory) await metadata.create(recursive: true);
    return File('${metadata.path}/$worktreeId.json');
  }
}
