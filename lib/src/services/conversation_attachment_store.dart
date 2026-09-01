import 'dart:io';
import 'dart:math';

import 'package:chatgpt/src/services/app_storage_scope.dart';

/// Stores images that must outlive the clipboard and the Flutter runtime.
class ConversationAttachmentStore {
  ConversationAttachmentStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;
  final Set<String> _createdPaths = <String>{};

  /// Image bytes remain plaintext so Flutter can render the durable path with
  /// `Image.file`. The encrypted conversation-history envelope stores only
  /// that path; this is deliberately a separate storage boundary.
  static const bool storesImageBytesEncryptedAtRest = false;

  /// Copies [paths] to application-managed storage and returns their new paths
  /// together with the files created for this attempt. Repeated source paths
  /// share one durable copy within the same request. If any copy fails, every
  /// file created by this invocation is removed before the failure escapes.
  Future<({Map<String, String> paths, List<String> createdPaths})> persist(
    Iterable<String> paths,
  ) async {
    final uniquePaths = paths.where((path) => path.isNotEmpty).toSet();
    if (uniquePaths.isEmpty) {
      return (paths: const <String, String>{}, createdPaths: const <String>[]);
    }

    final directory = _directory ?? _defaultDirectory();
    await directory.create(recursive: true);
    final copies = <String, String>{};
    final createdPaths = <String>[];
    try {
      for (final path in uniquePaths) {
        final source = File(path);
        if (!await source.exists()) {
          throw FileSystemException('找不到待保存的图片。', path);
        }
        final destination = File(
          '${directory.path}${Platform.pathSeparator}${_newFileName(path)}',
        );
        await source.copy(destination.path);
        createdPaths.add(destination.path);
        _createdPaths.add(destination.path);
        copies[path] = destination.path;
      }
    } catch (_) {
      await delete(createdPaths);
      rethrow;
    }
    return (paths: copies, createdPaths: createdPaths);
  }

  /// Deletes durable files made by this store when the associated submission
  /// was never accepted. Only paths created by this instance can be removed.
  Future<void> delete(Iterable<String> paths) async {
    for (final path in paths.toSet()) {
      if (!_createdPaths.remove(path)) continue;
      try {
        await File(path).delete();
      } on FileSystemException {
        // A concurrent cleanup or a manually removed file already achieved
        // the intended result. Keep the original submission failure useful.
      }
    }
  }

  /// Deletes durable copies that are no longer referenced by any local
  /// conversation. Unlike [delete], this also works for files created by a
  /// previous controller process (for example after a hot restart), while
  /// restricting deletion to this store's managed directory.
  Future<void> deleteManaged(Iterable<String> paths) async {
    final directory = (_directory ?? _defaultDirectory()).absolute;
    final root = '${directory.path}${Platform.pathSeparator}';
    for (final path in paths.toSet()) {
      final candidate = File(path).absolute.path;
      if (!candidate.startsWith(root)) continue;
      try {
        await File(candidate).delete();
      } on FileSystemException {
        // Missing files are already in the desired state.
      }
    }
  }

  Directory _defaultDirectory() => Directory(
    '${AppStorageScope.defaultDirectory().path}${Platform.pathSeparator}conversation-images',
  );

  String _newFileName(String sourcePath) {
    final fileName = sourcePath.split(Platform.pathSeparator).last;
    final dot = fileName.lastIndexOf('.');
    final extension = dot > 0 ? fileName.substring(dot) : '.png';
    return 'image-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}$extension';
  }
}
