import 'dart:async';

import 'package:chatgpt/src/services/clipboard_file_reader.dart';
import 'package:chatgpt/src/services/conversation_attachment_store.dart';

/// Owns temporary-composer attachment lifetime and durable-image persistence.
class CodexAttachmentCoordinator {
  CodexAttachmentCoordinator({
    required ConversationAttachmentStore store,
    required Set<String> temporaryPaths,
    required Map<String, int> composerRetains,
    required bool Function(String path) isReferenced,
    required bool Function(String path) isClipboardTemporaryPath,
  }) : _store = store,
       _temporaryPaths = temporaryPaths,
       _composerRetains = composerRetains,
       _isReferenced = isReferenced,
       _isClipboardTemporaryPath = isClipboardTemporaryPath;

  static const ClipboardFileReader clipboardFileReader = ClipboardFileReader();
  static final Map<String, int> temporaryOwnerCounts = {};

  final ConversationAttachmentStore _store;
  final Set<String> _temporaryPaths;
  final Map<String, int> _composerRetains;
  final bool Function(String path) _isReferenced;
  final bool Function(String path) _isClipboardTemporaryPath;

  Future<
    ({
      List<String> imagePaths,
      List<Map<String, dynamic>> additionalInput,
      List<String> createdImagePaths,
    })
  >
  persist({
    required List<String> imagePaths,
    required List<Map<String, dynamic>> additionalInput,
  }) async {
    final temporaryPaths = imagePaths
        .where(
          (path) =>
              _temporaryPaths.contains(path) || _isClipboardTemporaryPath(path),
        )
        .toSet();
    if (temporaryPaths.isEmpty) {
      return (
        imagePaths: imagePaths,
        additionalInput: additionalInput,
        createdImagePaths: const <String>[],
      );
    }
    final persisted = await _store.persist(temporaryPaths);
    final persistedPaths = persisted.paths;
    return (
      imagePaths: imagePaths
          .map((path) => persistedPaths[path] ?? path)
          .toList(growable: false),
      additionalInput: additionalInput
          .map((input) {
            final path = input['path'];
            if (input['type'] != 'localImage' || path is! String) return input;
            final persistedPath = persistedPaths[path];
            return persistedPath == null
                ? input
                : <String, dynamic>{...input, 'path': persistedPath};
          })
          .toList(growable: false),
      createdImagePaths: persisted.createdPaths,
    );
  }

  Future<void> discardUnreferenced(Iterable<String> paths) =>
      _store.delete(paths.where((path) => !_isReferenced(path)));

  Future<void> reclaimUnreferenced(Iterable<String> paths) async {
    final candidates = paths
        .where((path) => path.isNotEmpty && !_isReferenced(path))
        .toList(growable: false);
    if (candidates.isNotEmpty) await _store.deleteManaged(candidates);
  }

  void retain(String path) {
    if (path.isEmpty) return;
    if (_temporaryPaths.add(path)) {
      temporaryOwnerCounts.update(
        path,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    _composerRetains.update(path, (count) => count + 1, ifAbsent: () => 1);
  }

  void release(String path) {
    _decrementRetain(path);
    _releaseIfDetached(path);
  }

  void releaseDetached() {
    final detached = _temporaryPaths
        .where(
          (path) => (_composerRetains[path] ?? 0) == 0 && !_isReferenced(path),
        )
        .toList(growable: false);
    for (final path in detached) {
      _forget(path);
    }
  }

  void releaseAll() {
    final paths = _temporaryPaths.toList(growable: false);
    _composerRetains.clear();
    for (final path in paths) {
      _forget(path);
    }
  }

  void transferTo(String path, CodexAttachmentCoordinator target) {
    if (identical(this, target) || (_composerRetains[path] ?? 0) == 0) return;
    target.retain(path);
    _decrementRetain(path);
    releaseDetached();
  }

  void _decrementRetain(String path) {
    final count = _composerRetains[path];
    if (count == null) return;
    if (count <= 1) {
      _composerRetains.remove(path);
    } else {
      _composerRetains[path] = count - 1;
    }
  }

  void _releaseIfDetached(String path) {
    if ((_composerRetains[path] ?? 0) != 0 || _isReferenced(path)) return;
    _forget(path);
  }

  void _forget(String path) {
    if (!_temporaryPaths.remove(path)) return;
    final ownerCount = temporaryOwnerCounts[path] ?? 0;
    if (ownerCount > 1) {
      temporaryOwnerCounts[path] = ownerCount - 1;
      return;
    }
    temporaryOwnerCounts.remove(path);
    unawaited(clipboardFileReader.deleteTemporaryItem(path));
  }
}
