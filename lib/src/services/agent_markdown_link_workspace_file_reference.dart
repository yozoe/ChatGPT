// Extracted class from agent_markdown_link.dart.
import 'dart:io';

class WorkspaceFileReference {
  const WorkspaceFileReference({required this.uri, this.line, this.column});

  final Uri uri;
  final int? line;
  final int? column;

  String get path => uri.toFilePath(windows: Platform.isWindows);
}
