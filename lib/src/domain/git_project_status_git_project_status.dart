// Extracted class from git_project_status.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'git_project_status_support.dart';
import 'git_project_status_git_project_change.dart';

class GitProjectStatus {
  const GitProjectStatus({
    required this.isRepository,
    this.branch,
    this.changes = const [],
    this.error,
  });

  final bool isRepository;
  final String? branch;
  final List<GitProjectChange> changes;
  final String? error;

  /// 返回暂存、未暂存和未跟踪改动的数量摘要。
  /// Returns a count summary for staged, unstaged, and untracked changes.
  ({int staged, int unstaged, int untracked}) get changeCounts => (
    staged: changes.where((change) => change.isStaged).length,
    unstaged: changes.where((change) => change.isUnstaged).length,
    untracked: changes.where((change) => change.isUntracked).length,
  );

  /// 按状态和路径搜索返回改动列表，不改变 Git 工作区或原始顺序。
  /// Filters changes by status and path query without changing the worktree or source order.
  List<GitProjectChange> filteredChanges({
    GitChangeFilter filter = GitChangeFilter.all,
    String query = '',
  }) => changes
      .where(
        (change) => change.matchesFilter(filter) && change.matchesQuery(query),
      )
      .toList(growable: false);
}
