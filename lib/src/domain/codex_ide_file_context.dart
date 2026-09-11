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
