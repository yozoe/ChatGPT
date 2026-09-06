import 'package:chatgpt/src/presentation/workspace/workspace_file_tabs_state.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef WorkspaceFileTabsProviderArgument = ({
  Object scope,
  String? initialWorkspacePath,
});

final workspaceFileTabsProvider = NotifierProvider.family
    .autoDispose<
      WorkspaceFileTabsNotifier,
      WorkspaceFileTabsState,
      WorkspaceFileTabsProviderArgument
    >((argument) => WorkspaceFileTabsNotifier(argument.initialWorkspacePath));

String workspaceFileTabId(String path) => 'file:$path';

/// Coordinates retained project-file tabs for one workspace workbench.
class WorkspaceFileTabsNotifier extends Notifier<WorkspaceFileTabsState> {
  WorkspaceFileTabsNotifier(this.initialWorkspacePath);

  final String? initialWorkspacePath;

  @override
  WorkspaceFileTabsState build() =>
      WorkspaceFileTabsState(workspacePath: initialWorkspacePath);

  bool synchronizeWorkspace(String? workspacePath) {
    if (state.workspacePath == workspacePath) return false;
    state = WorkspaceFileTabsState(workspacePath: workspacePath);
    return true;
  }

  String? open(
    WorkspaceFileReference reference, {
    required String workspacePath,
  }) {
    if (state.workspacePath != workspacePath) return null;
    final tab = workspaceFileTabId(reference.path);
    state = WorkspaceFileTabsState(
      workspacePath: state.workspacePath,
      files: Map<String, WorkspaceFileReference>.unmodifiable({
        ...state.files,
        tab: reference,
      }),
    );
    return tab;
  }

  bool close(String tab) {
    if (!state.files.containsKey(tab)) return false;
    final files = Map<String, WorkspaceFileReference>.of(state.files)
      ..remove(tab);
    state = WorkspaceFileTabsState(
      workspacePath: state.workspacePath,
      files: Map<String, WorkspaceFileReference>.unmodifiable(files),
    );
    return true;
  }
}
