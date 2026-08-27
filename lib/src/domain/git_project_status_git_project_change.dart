// Extracted class from git_project_status.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'git_project_status_support.dart';

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
