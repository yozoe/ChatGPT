/// One IDE file and its current selection.
class CodexIdeFileContext {
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
    return CodexIdeFileContext(
      path: path,
      selectedText:
          value['activeSelectionContent']?.toString() ??
          value['selectedText']?.toString(),
      selectionRange: value['selectionRange'] is Map
          ? Map<String, Object?>.from(value['selectionRange'] as Map)
          : null,
    );
  }

  Map<String, Object?> toJson() => {
    'path': path,
    'selectedText': ?selectedText,
    'selectionRange': ?selectionRange,
  };
}
