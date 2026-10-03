/// Encrypted-content payload captured before a managed worktree is removed.
class WorktreeSnapshot {
  const WorktreeSnapshot({
    required this.snapshotId,
    required this.baseCommit,
    required this.trackedPatch,
    required this.files,
  });

  factory WorktreeSnapshot.fromJson(Map<Object?, Object?> json) {
    final rawFiles = json['files'];
    if (json['snapshotId'] is! String ||
        json['baseCommit'] is! String ||
        json['trackedPatch'] is! String ||
        rawFiles is! Map) {
      throw const FormatException('Worktree snapshot payload is invalid.');
    }
    return WorktreeSnapshot(
      snapshotId: json['snapshotId'] as String,
      baseCommit: json['baseCommit'] as String,
      trackedPatch: json['trackedPatch'] as String,
      files: Map.unmodifiable(
        rawFiles.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
      ),
    );
  }

  final String snapshotId;
  final String baseCommit;
  final String trackedPatch;
  final Map<String, String> files;

  Map<String, Object?> toJson() => {
    'version': 1,
    'snapshotId': snapshotId,
    'baseCommit': baseCommit,
    'trackedPatch': trackedPatch,
    'files': files,
  };
}
