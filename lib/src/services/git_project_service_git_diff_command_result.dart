// Extracted class from git_project_service.dart.

class GitDiffCommandResult {
  const GitDiffCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.truncated,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool truncated;
}
