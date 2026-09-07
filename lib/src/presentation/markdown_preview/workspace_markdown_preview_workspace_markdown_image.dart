// Extracted class from workspace_markdown_preview.dart.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_image_fallback.dart';

class WorkspaceMarkdownImage extends StatelessWidget {
  const WorkspaceMarkdownImage({
    required this.source,
    required this.alt,
    required this.workspacePath,
    required this.documentDirectoryPath,
    super.key,
  });

  final String source;
  final String? alt;
  final String workspacePath;
  final String documentDirectoryPath;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(source);
    if (uri != null &&
        const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      final description = alt?.trim();
      return ImageFallback(
        label: description == null || description.isEmpty
            ? '远程图片未自动载入'
            : '远程图片未自动载入：$description',
      );
    }
    return FutureBuilder<WorkspaceFileReference?>(
      future: resolveWorkspaceFileReference(
        href: source,
        workspacePath: workspacePath,
        relativeToDirectoryPath: documentDirectoryPath,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final reference = snapshot.data;
        if (reference == null) return ImageFallback(label: alt ?? '图片不可用');
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(reference.path),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  ImageFallback(label: alt ?? '图片不可用'),
            ),
          ),
        );
      },
    );
  }
}
