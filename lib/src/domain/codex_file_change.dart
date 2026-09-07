import 'dart:convert';

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

/// Splits a turn-wide Git patch into the files it changes.
///
/// The App Server may publish `turn/diff/updated` without a matching
/// `fileChange` item. Keeping the derived file records lets every consumer of
/// a task snapshot (the inspector, summary, and review) identify the same
/// files instead of treating a valid patch as an empty task.
List<CodexFileChange> codexFileChangesFromUnifiedDiff(String diff) {
  final headers = RegExp(
    r'^diff --git ("(?:\\.|[^"])*"|\S+) ("(?:\\.|[^"])*"|\S+)$',
    multiLine: true,
  ).allMatches(diff).toList(growable: false);
  return [
    for (var index = 0; index < headers.length; index++)
      (() {
        final header = headers[index];
        final sectionEnd = index + 1 < headers.length
            ? headers[index + 1].start
            : diff.length;
        final section = diff.substring(header.start, sectionEnd).trimRight();
        final kind = section.contains('\nnew file mode ')
            ? 'added'
            : section.contains('\ndeleted file mode ')
            ? 'deleted'
            : 'modified';
        return CodexFileChange(
          path: _pathFromGitDiffHeader(
            kind == 'deleted' ? header.group(1)! : header.group(2)!,
          ),
          kind: kind,
          diff: section,
        );
      })(),
  ];
}

String _pathFromGitDiffHeader(String value) {
  final quoted =
      value.length >= 2 && value.startsWith('"') && value.endsWith('"');
  final source = quoted ? value.substring(1, value.length - 1) : value;
  if (!quoted) return source.substring(2);

  final bytes = <int>[];
  final plain = StringBuffer();
  void flushPlain() {
    if (plain.isEmpty) return;
    bytes.addAll(utf8.encode(plain.toString()));
    plain.clear();
  }

  for (var index = 0; index < source.length; index++) {
    final codeUnit = source.codeUnitAt(index);
    if (codeUnit != 92 || index + 1 >= source.length) {
      plain.writeCharCode(codeUnit);
      continue;
    }
    flushPlain();
    final escaped = source[index + 1];
    if (RegExp(r'[0-7]').hasMatch(escaped) && index + 3 < source.length) {
      bytes.add(int.parse(source.substring(index + 1, index + 4), radix: 8));
      index += 3;
      continue;
    }
    bytes.add(switch (escaped) {
      't' => 9,
      'n' => 10,
      'r' => 13,
      _ => escaped.codeUnitAt(0),
    });
    index++;
  }
  flushPlain();
  final path = utf8.decode(bytes, allowMalformed: true);
  return path.substring(2);
}
