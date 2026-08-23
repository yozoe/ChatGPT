import 'package:flutter/services.dart';

/// A filesystem item copied through the host clipboard.
class ClipboardFileItem {
  const ClipboardFileItem({
    required this.path,
    required this.isDirectory,
    required this.isTemporary,
  });

  final String path;
  final bool isDirectory;
  final bool isTemporary;
}

/// Reads filesystem items copied through the host clipboard.
class ClipboardFileReader {
  const ClipboardFileReader();

  static const _channel = MethodChannel('codex_desk/clipboard');

  /// Returns files and directories from the clipboard, or an empty list
  /// when the platform has no file-aware clipboard implementation.
  Future<List<ClipboardFileItem>> readItems() async {
    try {
      final values = await _channel.invokeListMethod<Object?>('readFileItems');
      if (values == null) return const [];
      final seenPaths = <String>{};
      final items = <ClipboardFileItem>[];
      for (final value in values) {
        if (value is! Map) continue;
        final path = value['path'];
        if (path is! String || path.isEmpty || !seenPaths.add(path)) continue;
        items.add(
          ClipboardFileItem(
            path: path,
            isDirectory: value['isDirectory'] == true,
            isTemporary: value['isTemporary'] == true,
          ),
        );
      }
      return items;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Requests deletion of an image file created from clipboard bitmap data.
  Future<void> deleteTemporaryItem(String path) async {
    try {
      await _channel.invokeMethod<bool>('deleteTemporaryItem', path);
    } on MissingPluginException {
      // The host did not create a temporary clipboard item.
    } on PlatformException {
      // Temporary cleanup is best-effort and constrained by the native host.
    }
  }
}
