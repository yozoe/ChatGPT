import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:flutter/widgets.dart';

typedef WorkspaceFileOpenCallback =
    void Function(
      WorkspaceFileReference reference, {
      required String workspacePath,
    });

/// Exposes the current workbench file-tab action to conversation descendants.
class WorkspaceFileOpenScope extends InheritedWidget {
  const WorkspaceFileOpenScope({
    required this.onOpenFile,
    required super.child,
    super.key,
  });

  final WorkspaceFileOpenCallback onOpenFile;

  static WorkspaceFileOpenCallback? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<WorkspaceFileOpenScope>()
      ?.onOpenFile;

  @override
  bool updateShouldNotify(WorkspaceFileOpenScope oldWidget) =>
      onOpenFile != oldWidget.onOpenFile;
}
