import 'package:chatgpt/src/presentation/files/workspace_source_file_preview_state.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:flutter/material.dart';

/// Read-only source preview used by a conversation-opened workspace file tab.
class WorkspaceSourceFilePreview extends StatefulWidget {
  const WorkspaceSourceFilePreview({
    required this.reference,
    required this.workspacePath,
    required this.onClose,
    super.key,
  });

  final WorkspaceFileReference reference;
  final String workspacePath;
  final VoidCallback onClose;

  @override
  State<WorkspaceSourceFilePreview> createState() =>
      WorkspaceSourceFilePreviewState();
}
