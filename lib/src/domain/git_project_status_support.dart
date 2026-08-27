// Shared declarations extracted from git_project_status.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
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

/// 当前项目的只读 Git 工作区摘要；不会表示或执行任何写入操作。
/// A read-only Git working-tree summary for the current project; it represents and performs no write operations.

/// 只读 Diff 预览及其截断元数据。
/// A read-only diff preview and its truncation metadata.
