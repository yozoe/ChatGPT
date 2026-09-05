import 'package:chatgpt/src/presentation/files/codex_workspace_files_workspace_page_state.dart';
import 'package:flutter/material.dart';

/// A retained, read-only project file browser for the workspace side panel.
class FilesWorkspacePage extends StatefulWidget {
  const FilesWorkspacePage({
    required this.workspacePath,
    this.isVisible = true,
    super.key,
  });

  final String? workspacePath;
  final bool isVisible;

  @override
  State<FilesWorkspacePage> createState() => FilesWorkspacePageState();
}
