/// 时间线条目的渲染与语义类别；活动明细仍通过 command/tool 两类聚合。
/// Rendering and semantic category for a timeline entry; command/tool entries are grouped as activity details.
enum TimelineKind {
  system,
  user,
  agent,
  activity,
  command,
  tool,
  approval,
  error,
  elapsed,
}

/// 可持久化的单条对话时间线记录，不包含仅在运行时存在的活动状态。
/// One persistable conversation timeline record, excluding transient live activity.
class TimelineEntry {
  const TimelineEntry({
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
    this.imagePaths = const [],
    this.sourceItemId,
    this.activityKind,
    this.activityStatus,
  });

  final TimelineKind kind;
  final String title;
  final String detail;
  final DateTime createdAt;
  final List<String> imagePaths;

  /// App Server item identifier when this entry was reconstructed from one.
  final String? sourceItemId;

  /// Stable presentation category for a first-class conversation activity.
  final String? activityKind;

  /// Machine-readable lifecycle state retained for status styling.
  final String? activityStatus;

  /// 返回替换可选详情后的时间线条目副本。
  /// Returns a timeline entry copy with an optional replacement detail.
  TimelineEntry copyWith({
    String? title,
    String? detail,
    List<String>? imagePaths,
    String? sourceItemId,
    String? activityKind,
    String? activityStatus,
  }) {
    return TimelineEntry(
      kind: kind,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      createdAt: createdAt,
      imagePaths: imagePaths ?? this.imagePaths,
      sourceItemId: sourceItemId ?? this.sourceItemId,
      activityKind: activityKind ?? this.activityKind,
      activityStatus: activityStatus ?? this.activityStatus,
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
    'sourceItemId': ?sourceItemId,
    'activityKind': ?activityKind,
    'activityStatus': ?activityStatus,
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
      sourceItemId: value['sourceItemId']?.toString(),
      activityKind: value['activityKind']?.toString(),
      activityStatus: value['activityStatus']?.toString(),
    );
  }
}
