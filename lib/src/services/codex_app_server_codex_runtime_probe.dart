// Extracted class from codex_app_server.dart.

class CodexRuntimeProbe {
  const CodexRuntimeProbe({
    required this.isAvailable,
    this.executablePath,
    this.version,
    this.discovery,
    this.error,
  });

  final bool isAvailable;
  final String? executablePath;
  final String? version;
  final String? discovery;
  final String? error;
}
