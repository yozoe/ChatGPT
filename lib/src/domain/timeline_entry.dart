enum TimelineKind {
  system,
  user,
  agent,
  command,
  tool,
  approval,
  error,
  elapsed,
}

class TimelineEntry {
  const TimelineEntry({
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
    this.imagePaths = const [],
  });

  final TimelineKind kind;
  final String title;
  final String detail;
  final DateTime createdAt;
  final List<String> imagePaths;

  /// 返回替换可选详情后的时间线条目副本。
  /// Returns a timeline entry copy with an optional replacement detail.
  TimelineEntry copyWith({String? detail, List<String>? imagePaths}) {
    return TimelineEntry(
      kind: kind,
      title: title,
      detail: detail ?? this.detail,
      createdAt: createdAt,
      imagePaths: imagePaths ?? this.imagePaths,
    );
  }

  /// 将时间线条目转换为本地历史缓存使用的 JSON。
  /// Converts the timeline entry to JSON for the local history cache.
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'title': title,
    'detail': detail,
    'createdAt': createdAt.toIso8601String(),
    'imagePaths': imagePaths,
  };

  /// 从本地历史缓存 JSON 恢复时间线条目。
  /// Restores a timeline entry from local history cache JSON.
  factory TimelineEntry.fromJson(Map<dynamic, dynamic> value) {
    final kind = TimelineKind.values.where(
      (candidate) => candidate.name == value['kind']?.toString(),
    );
    return TimelineEntry(
      kind: kind.isEmpty ? TimelineKind.system : kind.first,
      title: value['title']?.toString() ?? '',
      detail: value['detail']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(value['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      imagePaths: (value['imagePaths'] is Iterable
          ? (value['imagePaths'] as Iterable)
                .map((path) => path.toString())
                .toList(growable: false)
          : const <String>[]),
    );
  }
}
