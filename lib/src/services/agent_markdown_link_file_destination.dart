// Extracted class from agent_markdown_link.dart.

class FileDestination {
  const FileDestination(this.value, {this.line, this.column});

  final String value;
  final int? line;
  final int? column;
}
