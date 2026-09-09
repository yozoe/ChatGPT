import 'dart:io';

/// 工作区文件树中展示的单个文件系统项目。
/// A single filesystem item shown in the workspace file tree.
class CodexWorkspaceFileEntry {
  const CodexWorkspaceFileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
  });

  factory CodexWorkspaceFileEntry.fromFileSystemEntity(
    FileSystemEntity entity,
  ) {
    final pathSegments = entity.uri.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    return CodexWorkspaceFileEntry(
      path: entity.path,
      name: pathSegments.isEmpty ? entity.path : pathSegments.last,
      isDirectory: entity is Directory,
    );
  }

  final String path;
  final String name;
  final bool isDirectory;

  bool matchesNameQuery(String query) =>
      query.isEmpty || isDirectory || name.toLowerCase().contains(query);
}
