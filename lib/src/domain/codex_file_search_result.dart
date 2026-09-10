import 'dart:io';

/// A file or directory match returned by Codex App Server fuzzy file search.
class CodexFileSearchResult {
  const CodexFileSearchResult({
    required this.fileName,
    required this.path,
    required this.root,
    required this.matchType,
    required this.score,
    required this.indices,
  });

  factory CodexFileSearchResult.fromJson(Map<dynamic, dynamic> value) {
    final fileName = value['file_name']?.toString().trim() ?? '';
    final path = value['path']?.toString().trim() ?? '';
    final root = value['root']?.toString().trim() ?? '';
    final matchType = value['match_type']?.toString().trim() ?? '';
    final rawScore = value['score'];
    if (fileName.isEmpty ||
        path.isEmpty ||
        root.isEmpty ||
        (matchType != 'file' && matchType != 'directory') ||
        rawScore is! num ||
        rawScore < 0 ||
        rawScore.toInt() != rawScore) {
      throw const FormatException('Invalid fuzzy file search result.');
    }
    final rawIndices = value['indices'];
    final indices = <int>[];
    if (rawIndices != null) {
      if (rawIndices is! Iterable) {
        throw const FormatException('Invalid fuzzy file match indices.');
      }
      for (final rawIndex in rawIndices) {
        if (rawIndex is! num || rawIndex < 0 || rawIndex.toInt() != rawIndex) {
          throw const FormatException('Invalid fuzzy file match index.');
        }
        indices.add(rawIndex.toInt());
      }
    }
    return CodexFileSearchResult(
      fileName: fileName,
      path: path,
      root: root,
      matchType: matchType,
      score: rawScore.toInt(),
      indices: List.unmodifiable(indices),
    );
  }

  final String fileName;
  final String path;
  final String root;
  final String matchType;
  final int score;
  final List<int> indices;

  bool get isDirectory => matchType == 'directory';

  /// Resolves the protocol path against its root without touching the file.
  String get candidatePath {
    if (path.startsWith(Platform.pathSeparator)) return path;
    final relative = path.replaceAll('/', Platform.pathSeparator);
    return root.endsWith(Platform.pathSeparator)
        ? '$root$relative'
        : '$root${Platform.pathSeparator}$relative';
  }

  CodexFileSearchResult withPath(String resolvedPath) => CodexFileSearchResult(
    fileName: fileName,
    path: resolvedPath,
    root: root,
    matchType: matchType,
    score: score,
    indices: indices,
  );
}
