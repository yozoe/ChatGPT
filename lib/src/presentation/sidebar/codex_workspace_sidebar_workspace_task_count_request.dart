// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class WorkspaceTaskCountRequest {
  const WorkspaceTaskCountRequest({
    required this.controller,
    required this.path,
  });

  final CodexController controller;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceTaskCountRequest &&
      identical(other.controller, controller) &&
      other.path == path;

  @override
  int get hashCode => Object.hash(identityHashCode(controller), path);
}
