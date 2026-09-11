/// One IDE file and its current selection.
class CodexIdeFileContext {
  static const maximumSelectedTextLength = 64000;
  const CodexIdeFileContext({
    required this.path,
    this.selectedText,
    this.selectionRange,
  });
  final String path;
  final String? selectedText;
  final Map<String, Object?>? selectionRange;

  static CodexIdeFileContext? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['fsPath']?.toString() ?? value['path']?.toString();
    if (path == null || path.trim().isEmpty) return null;
    final selectedText =
        value['activeSelectionContent']?.toString() ??
        value['selectedText']?.toString();
    return CodexIdeFileContext(
      path: path,
      selectedText: selectedText == null
          ? null
          : selectedText.length > maximumSelectedTextLength
          ? selectedText.substring(0, maximumSelectedTextLength)
          : selectedText,
      selectionRange: _parseSelectionRange(value['selectionRange']),
    );
  }

  static Map<String, Object?>? _parseSelectionRange(Object? value) {
    if (value is! Map) return null;
    final start = value['start'];
    final end = value['end'];
    if (start is! Map || end is! Map) return null;
    final startLine = start['line'];
    final startCharacter = start['character'];
    final endLine = end['line'];
    final endCharacter = end['character'];
    if (startLine is! int ||
        startCharacter is! int ||
        endLine is! int ||
        endCharacter is! int ||
        startLine < 0 ||
        startCharacter < 0 ||
        endLine < startLine ||
        endCharacter < 0 ||
        (endLine == startLine && endCharacter < startCharacter)) {
      return null;
    }
    return {
      'start': {'line': startLine, 'character': startCharacter},
      'end': {'line': endLine, 'character': endCharacter},
    };
  }

  Map<String, Object?> toJson() => {
    'path': path,
    'selectedText': ?selectedText,
    'selectionRange': ?selectionRange,
  };
}
