import 'codex_ide_file_context.dart';

/// Context supplied by an attached IDE host for one Composer turn.
class CodexIdeContext {
  const CodexIdeContext({this.activeFile, this.openTabs = const []});

  final CodexIdeFileContext? activeFile;
  final List<CodexIdeFileContext> openTabs;

  bool get isAvailable => activeFile != null || openTabs.isNotEmpty;

  factory CodexIdeContext.fromJson(Object? value) {
    if (value is! Map) return const CodexIdeContext();
    return CodexIdeContext(
      activeFile: CodexIdeFileContext.fromJson(value['activeFile']),
      openTabs: (value['openTabs'] is Iterable
          ? (value['openTabs'] as Iterable)
                .map(CodexIdeFileContext.fromJson)
                .whereType<CodexIdeFileContext>()
                .toList(growable: false)
          : const []),
    );
  }

  Map<String, Object?> toJson() => {
    if (activeFile case final file?) 'activeFile': file.toJson(),
    'openTabs': openTabs.map((file) => file.toJson()).toList(),
  };
}
