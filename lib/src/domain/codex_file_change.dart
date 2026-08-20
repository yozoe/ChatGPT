class CodexFileChange {
  const CodexFileChange({
    required this.path,
    required this.kind,
    required this.diff,
  });

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

  CodexFileChange copyWith({String? kind, String? diff}) {
    return CodexFileChange(
      path: path,
      kind: kind ?? this.kind,
      diff: diff ?? this.diff,
    );
  }

  Map<String, dynamic> toJson() => {'path': path, 'kind': kind, 'diff': diff};

  @override
  bool operator ==(Object other) =>
      other is CodexFileChange &&
      path == other.path &&
      kind == other.kind &&
      diff == other.diff;

  @override
  int get hashCode => Object.hash(path, kind, diff);
}
