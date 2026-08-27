// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';

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
