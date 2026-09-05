import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/presentation/files/workspace_file_preview.dart';

/// Reads a bounded UTF-8 preview after resolving the workspace security
/// boundary and any symbolic links.
class WorkspaceFilePreviewReader {
  const WorkspaceFilePreviewReader({
    required this.workspacePath,
    required this.maximumBytes,
  });

  static const String outsideWorkspaceMessage = '无法预览工作区以外的文件。';
  static const String tooLargeMessage = '文件超过 1 MB，未在此处加载。';
  static const String binaryMessage = '无法预览二进制文件。';
  static const String invalidEncodingMessage = '仅支持预览 UTF-8 文本文件。';
  static const String unreadableMessage = '无法读取此文件。';

  final String workspacePath;
  final int maximumBytes;

  Future<WorkspaceFilePreview> read(String path) async {
    try {
      final resolvedWorkspace = await Directory(
        workspacePath,
      ).resolveSymbolicLinks();
      final resolvedPath = await File(path).resolveSymbolicLinks();
      if (!_isWithinWorkspace(resolvedWorkspace, resolvedPath)) {
        return const WorkspaceFilePreview.error(outsideWorkspaceMessage);
      }
      final bytes = await File(resolvedPath)
          .openRead(0, maximumBytes + 1)
          .fold<List<int>>(<int>[], (buffer, chunk) {
            buffer.addAll(chunk);
            return buffer;
          });
      if (bytes.length > maximumBytes) {
        return const WorkspaceFilePreview.error(tooLargeMessage);
      }
      if (bytes.any((byte) => byte == 0)) {
        return const WorkspaceFilePreview.error(binaryMessage);
      }
      return WorkspaceFilePreview.content(utf8.decode(bytes));
    } on FormatException {
      return const WorkspaceFilePreview.error(invalidEncodingMessage);
    } on FileSystemException {
      return const WorkspaceFilePreview.error(unreadableMessage);
    }
  }

  static bool _isWithinWorkspace(String workspace, String path) =>
      path == workspace ||
      path.startsWith('$workspace${Platform.pathSeparator}');
}
