enum TimelineKind { system, user, agent, command, approval, error }

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
}
