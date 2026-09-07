// Extracted class from workspace_markdown_preview.dart.
import 'package:flutter/material.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_workspace_markdown_preview_state.dart';

class WorkspaceMarkdownPreview extends StatefulWidget {
  const WorkspaceMarkdownPreview({
    required this.reference,
    required this.workspacePath,
    this.embedded = false,
    this.onClose,
    this.onOpenReference,
    super.key,
  });

  final WorkspaceFileReference reference;
  final String workspacePath;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<WorkspaceFileReference>? onOpenReference;

  @override
  State<WorkspaceMarkdownPreview> createState() =>
      WorkspaceMarkdownPreviewState();
}
