import 'dart:io';

/// 用户主动点击 Markdown 链接时调用的平台外部打开器。
/// Platform external-link launcher called only after a user activates Markdown content.
typedef AgentMarkdownUriLauncher = Future<bool> Function(Uri uri);

/// Opens a Markdown link from an agent reply.
///
/// Web and email links retain their normal behavior. Relative links and
/// `file:` links are resolved against the active workspace, but only when the
/// resolved file remains inside that workspace. This lets an agent point to a
/// generated document without granting a reply access to unrelated local
/// files.
Future<bool> openAgentMarkdownLink({
  required String? href,
  required String? workspacePath,
  required AgentMarkdownUriLauncher launch,
}) async {
  if (href == null || href.trim().isEmpty) return false;
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return false;

  if (const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase())) {
    return launch(uri);
  }

  final fileUri = await resolveWorkspaceFileLink(
    href: href,
    workspacePath: workspacePath,
  );
  return fileUri == null ? false : launch(fileUri);
}

/// Resolves a relative or `file:` Markdown destination to a local workspace
/// file. Returns null for missing files and destinations outside the project.
Future<Uri?> resolveWorkspaceFileLink({
  required String href,
  required String? workspacePath,
}) async {
  if (workspacePath == null || workspacePath.trim().isEmpty) return null;
  final uri = Uri.tryParse(href.trim());
  if (uri == null || !{'', 'file'}.contains(uri.scheme.toLowerCase())) {
    return null;
  }
  if (uri.scheme == 'file' && uri.host.isNotEmpty && uri.host != 'localhost') {
    return null;
  }

  final path = uri.scheme == 'file' ? uri.toFilePath() : uri.path;
  if (path.isEmpty || path.contains('\u0000')) return null;
  final isAbsolute =
      uri.scheme == 'file' ||
      path.startsWith(Platform.pathSeparator) ||
      (Platform.isWindows && RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path));
  final candidate = File(
    isAbsolute ? path : '$workspacePath${Platform.pathSeparator}$path',
  );

  try {
    final workspace = await Directory(workspacePath).resolveSymbolicLinks();
    final file = await candidate.resolveSymbolicLinks();
    final workspacePrefix = '$workspace${Platform.pathSeparator}';
    if (!file.startsWith(workspacePrefix)) return null;
    if (!await File(file).exists()) return null;
    return Uri.file(file, windows: Platform.isWindows);
  } on FileSystemException {
    return null;
  }
}
