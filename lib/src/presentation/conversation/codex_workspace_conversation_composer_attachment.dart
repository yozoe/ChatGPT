// Extracted class from codex_workspace_conversation.dart.

class ComposerAttachment {
  const ComposerAttachment({
    required this.path,
    required this.isDirectory,
    this.isTemporary = false,
  });

  final String path;
  final bool isDirectory;
  final bool isTemporary;
}
