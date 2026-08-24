import 'package:flutter/services.dart';

/// 主机剪贴板公开给 Flutter 的文件系统项；临时项由原生层负责受限清理。
/// A filesystem item exposed by the host clipboard; native code owns constrained temporary cleanup.
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

/// 通过受限 MethodChannel 读取主机剪贴板文件，不读取普通文本内容。
/// Reads host clipboard files through a constrained MethodChannel without reading normal text.
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
