enum TimelineKind { system, user, agent, command, tool, approval, error }

class TimelineEntry {
  const TimelineEntry({
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
  });

  final TimelineKind kind;
  final String title;
  final String detail;
  final DateTime createdAt;

  TimelineEntry copyWith({String? detail}) {
    return TimelineEntry(
      kind: kind,
      title: title,
      detail: detail ?? this.detail,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'title': title,
    'detail': detail,
    'createdAt': createdAt.toIso8601String(),
  };

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
    );
  }
}
