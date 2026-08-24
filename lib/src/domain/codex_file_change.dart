/// 一项由 App Server 报告、可带有统一 Diff 的文件变更。
/// One App Server-reported file change with an optional unified diff.
class CodexFileChange {
  const CodexFileChange({
    required this.path,
    required this.kind,
    required this.diff,
  });

  /// 从 App Server 的文件变更数据创建不可变对象。
  /// Creates an immutable value from App Server file-change data.
  factory CodexFileChange.fromJson(Map<dynamic, dynamic> value) {
    return CodexFileChange(
      path: value['path']?.toString() ?? value['filePath']?.toString() ?? '',
      kind: value['kind']?.toString() ?? value['type']?.toString() ?? 'changed',
      diff: value['diff']?.toString() ?? '',
    );
  }

  final String path;
  final String kind;
  final String diff;

  /// 返回替换可选变更字段后的副本。
  /// Returns a copy with optional change fields replaced.
  CodexFileChange copyWith({String? kind, String? diff}) {
    return CodexFileChange(
      path: path,
      kind: kind ?? this.kind,
      diff: diff ?? this.diff,
    );
  }

  /// 将文件变更转换为本地历史缓存使用的 JSON。
  /// Converts the file change to JSON for the local history cache.
  Map<String, dynamic> toJson() => {'path': path, 'kind': kind, 'diff': diff};

  /// 按路径、变更类型和 Diff 判断值是否相同。
  /// Compares values by path, change kind, and diff.
  @override
  bool operator ==(Object other) =>
      other is CodexFileChange &&
      path == other.path &&
      kind == other.kind &&
      diff == other.diff;

  @override
  int get hashCode => Object.hash(path, kind, diff);
}
