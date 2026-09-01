import 'dart:io';

import 'package:chatgpt/src/domain/workspace_configuration.dart';

/// Applies the filesystem safety rules shared by workspace selection and restore.
class CodexWorkspacePaths {
  Future<String?> canonicalProjectDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return null;
    final canonicalPath = await directory.resolveSymbolicLinks();
    return await isSystemTemporaryDirectory(canonicalPath)
        ? null
        : canonicalPath;
  }

  Future<WorkspaceConfiguration?> restoreConfiguration(
    WorkspaceConfiguration stored, {
    required String Function() newProjectId,
  }) async {
    if (stored.isUnrooted) {
      return WorkspaceConfiguration(
        id: stored.id ?? newProjectId(),
        primaryPath: stored.primaryPath,
        name: stored.name,
      );
    }
    final primaryDirectory = Directory(stored.primaryPath);
    if (stored.primaryPath.isEmpty || !await primaryDirectory.exists()) {
      return null;
    }
    try {
      final primaryPath = await primaryDirectory.resolveSymbolicLinks();
      if (await isSystemTemporaryDirectory(primaryPath)) return null;
      final additionalPaths = <String>[];
      for (final storedAdditional in stored.additionalPaths) {
        final directory = Directory(storedAdditional);
        if (!await directory.exists()) continue;
        final canonicalPath = await directory.resolveSymbolicLinks();
        if (!await isSystemTemporaryDirectory(canonicalPath) &&
            canonicalPath != primaryPath &&
            !additionalPaths.contains(canonicalPath)) {
          additionalPaths.add(canonicalPath);
        }
      }
      return WorkspaceConfiguration(
        id: stored.id ?? newProjectId(),
        primaryPath: primaryPath,
        additionalPaths: additionalPaths,
        name: stored.name,
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> isSystemTemporaryDirectory(String canonicalPath) async {
    try {
      return canonicalPath == await Directory.systemTemp.resolveSymbolicLinks();
    } on FileSystemException {
      return false;
    }
  }
}
