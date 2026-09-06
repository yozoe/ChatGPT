import 'package:chatgpt/src/services/agent_markdown_link.dart';

/// Immutable file-tab snapshot owned by one workspace workbench instance.
class WorkspaceFileTabsState {
  const WorkspaceFileTabsState({
    required this.workspacePath,
    this.files = const <String, WorkspaceFileReference>{},
  });

  final String? workspacePath;
  final Map<String, WorkspaceFileReference> files;
}
