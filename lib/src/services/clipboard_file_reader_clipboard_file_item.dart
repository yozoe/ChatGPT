// Extracted class from clipboard_file_reader.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:flutter/services.dart';
import 'clipboard_file_reader_support.dart';

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
