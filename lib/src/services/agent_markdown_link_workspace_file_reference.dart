// Extracted class from agent_markdown_link.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:io';
import 'agent_markdown_link_support.dart';

class WorkspaceFileReference {
  const WorkspaceFileReference({required this.uri, this.line, this.column});

  final Uri uri;
  final int? line;
  final int? column;

  String get path => uri.toFilePath(windows: Platform.isWindows);
}
