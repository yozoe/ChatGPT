/// 只读 Git 文件列表支持的筛选范围。
/// Filter scopes supported by the read-only Git change list.
enum GitChangeFilter { all, staged, unstaged, untracked }

extension GitChangeFilterLabel on GitChangeFilter {
  /// 返回筛选项在界面中的本地化名称。
  /// Returns the localized label used by the filter control.
  String get label => switch (this) {
    GitChangeFilter.all => '全部',
    GitChangeFilter.staged => '暂存',
    GitChangeFilter.unstaged => '未暂存',
    GitChangeFilter.untracked => '未跟踪',
  };
}

/// 表示 Git 工作区中的单个未提交文件状态；不包含文件内容。
/// Represents one uncommitted Git working-tree file status without file contents.
class GitProjectChange {
  const GitProjectChange({
    required this.code,
    required this.path,
    this.previousPath,
  });

  final String code;
  final String path;
  final String? previousPath;

  /// 指示文件是否尚未被 Git 跟踪。
  /// Returns whether the file is not yet tracked by Git.
  bool get isUntracked => code == '??';

  /// 指示改动是否包含暂存区状态。
  /// Returns whether the change includes an index (staged) status.
  bool get isStaged => code.isNotEmpty && code[0] != ' ' && code[0] != '?';

  /// 指示改动是否包含工作区但未暂存的状态。
  /// Returns whether the change includes an unstaged working-tree status.
  bool get isUnstaged => code.length > 1 && code[1] != ' ' && code[1] != '?';

  /// 返回用于界面展示的简短 Git 状态文本。
  /// Returns a short Git status label for the interface.
  String get label => switch (code) {
    '??' => '未跟踪',
    '!!' => '已忽略',
    _ when code.contains('R') => '重命名',
    _ when code.contains('C') => '复制',
    _ when code.contains('A') => '新增',
    _ when code.contains('D') => '删除',
    _ when code.contains('M') => '已修改',
    _ => code.trim().isEmpty ? '已变更' : code,
  };

  /// 判断改动是否属于指定筛选范围。
  /// Returns whether the change belongs to the requested filter scope.
  bool matchesFilter(GitChangeFilter filter) => switch (filter) {
    GitChangeFilter.all => true,
    GitChangeFilter.staged => isStaged,
    GitChangeFilter.unstaged => isUnstaged,
    GitChangeFilter.untracked => isUntracked,
  };

  /// 判断当前路径或重命名前路径是否包含搜索词，比较时忽略大小写。
  /// Matches the current or previous path against a case-insensitive query.
  bool matchesQuery(String query) {
    final value = query.trim().toLowerCase();
    if (value.isEmpty) return true;
    return path.toLowerCase().contains(value) ||
        (previousPath?.toLowerCase().contains(value) ?? false);
  }
}

/// 当前项目的只读 Git 工作区摘要；不会表示或执行任何写入操作。
/// A read-only Git working-tree summary for the current project; it represents and performs no write operations.
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

/// 只读 Diff 预览及其截断元数据。
/// A read-only diff preview and its truncation metadata.
class GitDiffPreview {
  const GitDiffPreview({required this.content, required this.truncated});

  final String content;
  final bool truncated;
}
