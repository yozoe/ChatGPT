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
  TimelineEntry({
    String? id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
    this.imagePaths = const [],
    this.sourceItemId,
    this.activityKind,
    this.activityStatus,
    this.agentPhase,
    this.linkedThreadId,
    this.activityPrompt,
  }) : id = id == null || id.trim().isEmpty ? _newId() : id.trim();

  static int _idSequence = 0;

  static String _newId() =>
      'timeline-${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';

  /// 在流式副本和历史恢复之间保持不变的本地标识。
  /// Stable local identity retained across streaming copies and history reloads.
  final String id;

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

  /// App Server agent-message phase (`commentary` or `final_answer`).
  final String? agentPhase;

  /// 协作活动对应的子线程；非协作条目保持为空。
  /// Child thread associated with a collaboration activity; null otherwise.
  final String? linkedThreadId;

  /// App Server 为子智能体提供的原始任务说明。
  /// Original task prompt supplied by App Server for a subagent.
  final String? activityPrompt;

  /// 返回替换可选详情后的时间线条目副本。
  /// Returns a timeline entry copy with an optional replacement detail.
  TimelineEntry copyWith({
    String? title,
    String? detail,
    List<String>? imagePaths,
    String? sourceItemId,
    String? activityKind,
    String? activityStatus,
    String? agentPhase,
    String? linkedThreadId,
    String? activityPrompt,
  }) {
    return TimelineEntry(
      id: id,
      kind: kind,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      createdAt: createdAt,
      imagePaths: imagePaths ?? this.imagePaths,
      sourceItemId: sourceItemId ?? this.sourceItemId,
      activityKind: activityKind ?? this.activityKind,
      activityStatus: activityStatus ?? this.activityStatus,
      agentPhase: agentPhase ?? this.agentPhase,
      linkedThreadId: linkedThreadId ?? this.linkedThreadId,
      activityPrompt: activityPrompt ?? this.activityPrompt,
    );
  }

  /// 将时间线条目转换为本地历史缓存使用的 JSON。
  /// Converts the timeline entry to JSON for the local history cache.
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'detail': detail,
    'createdAt': createdAt.toIso8601String(),
    'imagePaths': imagePaths,
    'sourceItemId': ?sourceItemId,
    'activityKind': ?activityKind,
    'activityStatus': ?activityStatus,
    'agentPhase': ?agentPhase,
    'linkedThreadId': ?linkedThreadId,
    'activityPrompt': ?activityPrompt,
  };

  /// 从本地历史缓存 JSON 恢复时间线条目。
  /// Restores a timeline entry from local history cache JSON.
  factory TimelineEntry.fromJson(Map<dynamic, dynamic> value) {
    final kind = TimelineKind.values.where(
      (candidate) => candidate.name == value['kind']?.toString(),
    );
    return TimelineEntry(
      id: value['id']?.toString(),
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
      agentPhase: value['agentPhase']?.toString(),
      linkedThreadId: value['linkedThreadId']?.toString(),
      activityPrompt: value['activityPrompt']?.toString(),
    );
  }
}
