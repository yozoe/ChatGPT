// Shared declarations extracted from agent_markdown_link.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:io';
import 'agent_markdown_link_workspace_file_reference.dart';
import 'agent_markdown_link_file_destination.dart';
import 'dart:io';

/// 用户主动点击 Markdown 链接时调用的平台外部打开器。
/// Platform external-link launcher called only after a user activates Markdown content.
typedef AgentMarkdownUriLauncher = Future<bool> Function(Uri uri);

/// A workspace-local file resolved from Markdown, including optional Codex
/// source-location metadata.

bool isMarkdownFilePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.markdown');
}

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
  if (uri != null &&
      const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase())) {
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
  String? relativeToDirectoryPath,
}) async {
  final reference = await resolveWorkspaceFileReference(
    href: href,
    workspacePath: workspacePath,
    relativeToDirectoryPath: relativeToDirectoryPath,
  );
  return reference?.uri;
}

/// Resolves a workspace-local Markdown destination without allowing path or
/// symbolic-link traversal beyond the active project.
Future<WorkspaceFileReference?> resolveWorkspaceFileReference({
  required String href,
  required String? workspacePath,
  String? relativeToDirectoryPath,
}) async {
  if (workspacePath == null || workspacePath.trim().isEmpty) return null;
  try {
    final workspace = await Directory(workspacePath).resolveSymbolicLinks();
    final destinations = <FileDestination>[FileDestination(href.trim())];
    final location = _textLocation(href.trim());
    if (location != null && location.destination != destinations.first.value) {
      destinations.add(
        FileDestination(
          location.destination,
          line: location.line,
          column: location.column,
        ),
      );
    }

    for (final destination in destinations) {
      final localPath = _localFilePath(destination.value);
      if (localPath == null || localPath.path.contains('\u0000')) continue;
      final candidate = File(
        localPath.isAbsolute
            ? localPath.path
            : '${relativeToDirectoryPath ?? workspacePath}'
                  '${Platform.pathSeparator}${localPath.path}',
      );
      try {
        final file = await candidate.resolveSymbolicLinks();
        final workspacePrefix = '$workspace${Platform.pathSeparator}';
        if (file != workspace && !file.startsWith(workspacePrefix)) continue;
        if (!await File(file).exists()) continue;
        return WorkspaceFileReference(
          uri: Uri.file(file, windows: Platform.isWindows),
          line: destination.line,
          column: destination.column,
        );
      } on FileSystemException {
        continue;
      }
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

({String path, bool isAbsolute})? _localFilePath(String destination) {
  final isWindowsAbsolute = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(destination);
  if (isWindowsAbsolute) {
    if (!Platform.isWindows) return null;
    return (path: destination, isAbsolute: true);
  }

  final uri = Uri.tryParse(destination);
  if (uri == null || !{'', 'file'}.contains(uri.scheme.toLowerCase())) {
    return null;
  }
  if (uri.host.isNotEmpty && uri.host != 'localhost') return null;

  try {
    final path = uri.scheme == 'file'
        ? uri.toFilePath()
        : Uri.decodeComponent(uri.path);
    if (path.isEmpty) return null;
    return (
      path: path,
      isAbsolute:
          uri.scheme == 'file' || path.startsWith(Platform.pathSeparator),
    );
  } on FormatException {
    return null;
  } on UnsupportedError {
    return null;
  }
}

/// Codex file references can append `:line` or `:line:column` to their target.
/// The suffix is editor metadata rather than part of the file name. The exact
/// destination is still tried first so a real POSIX file ending in digits is
/// not shadowed.
({String destination, int line, int? column})? _textLocation(
  String destination,
) {
  final match = RegExp(
    r'^(.*?):([1-9][0-9]*)(?::([1-9][0-9]*))?([?#].*)?$',
  ).firstMatch(destination);
  if (match == null) return null;

  final fileTarget = match.group(1)!;
  final looksLikeFileTarget =
      fileTarget.toLowerCase().startsWith('file:') ||
      fileTarget.startsWith('/') ||
      fileTarget.startsWith('./') ||
      fileTarget.startsWith('../') ||
      fileTarget.contains('/') ||
      fileTarget.contains(r'\') ||
      fileTarget.split(RegExp(r'[/\\]')).last.contains('.');
  if (!looksLikeFileTarget) return null;
  return (
    destination: '$fileTarget${match.group(4) ?? ''}',
    line: int.parse(match.group(2)!),
    column: switch (match.group(3)) {
      final value? => int.parse(value),
      null => null,
    },
  );
}
