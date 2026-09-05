/// Structured, user-displayable error returned by a Codex App Server request.
class CodexAppServerException implements Exception {
  const CodexAppServerException({required this.message, this.code, this.type});

  final String message;
  final Object? code;
  final String? type;

  @override
  String toString() => message;
}
