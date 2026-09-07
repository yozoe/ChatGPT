// Extracted class from codex_workspace_conversation.dart.

class DiffStats {
  const DiffStats(this.additions, this.deletions);

  final int additions;
  final int deletions;

  DiffStats operator +(DiffStats other) =>
      DiffStats(additions + other.additions, deletions + other.deletions);
}
