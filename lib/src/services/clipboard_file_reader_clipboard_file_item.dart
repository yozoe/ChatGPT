// Extracted class from clipboard_file_reader.dart.

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
