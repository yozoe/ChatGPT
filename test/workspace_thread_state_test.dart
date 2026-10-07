import 'package:chatgpt/src/app_controller_workspace_thread_state.dart';
import 'package:chatgpt/src/app_controller_workspace_task_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'clears inactive workspace task previews without losing workspace config',
    () {
      final state = CodexWorkspaceThreadState()
        ..workspacePath = '/project'
        ..workspaceTaskLists['/other'] = const WorkspaceTaskList(
          threads: [],
          pinnedIds: {},
          acknowledgedIds: {},
        )
        ..workspaceTaskListLoadEpoch = 4;

      state.clearWorkspaceTaskLists();

      expect(state.workspacePath, '/project');
      expect(state.workspaceTaskLists, isEmpty);
      expect(state.workspaceTaskListLoadEpoch, 5);
    },
  );

  test('clear resets active thread and cached history ownership', () {
    final state = CodexWorkspaceThreadState()
      ..workspacePath = '/project'
      ..activeThreadId = 'thread-1'
      ..activeThreadAttached = true
      ..ownedThreadIds.add('thread-1')
      ..pinnedThreadIds.add('thread-1')
      ..runningThreadIds.add('thread-1')
      ..threadWorkspaceById['thread-1'] = '/project'
      ..managedWorktreeIdByThread['thread-1'] = 'worktree-1'
      ..threadHistoryInitialized = true;

    state.clear();

    expect(state.workspacePath, isNull);
    expect(state.activeThreadId, isNull);
    expect(state.activeThreadAttached, isFalse);
    expect(state.ownedThreadIds, isEmpty);
    expect(state.pinnedThreadIds, isEmpty);
    expect(state.runningThreadIds, isEmpty);
    expect(state.threadWorkspaceById, isEmpty);
    expect(state.managedWorktreeIdByThread, isEmpty);
    expect(state.threadHistoryInitialized, isFalse);
  });

  test(
    'clearRuntimeOwnership preserves workspace and selected thread state',
    () {
      final state = CodexWorkspaceThreadState()
        ..workspacePath = '/workspace'
        ..activeThreadId = 'thread-1'
        ..activeThreadAttached = true
        ..runningThreadIds.add('thread-1')
        ..threadWorkspaceById['thread-1'] = '/workspace';

      state.clearRuntimeOwnership();

      expect(state.workspacePath, '/workspace');
      expect(state.activeThreadId, 'thread-1');
      expect(state.activeThreadAttached, isFalse);
      expect(state.runningThreadIds, isEmpty);
      expect(state.threadWorkspaceById, isEmpty);
    },
  );
}
