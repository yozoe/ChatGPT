/// 双端 Worktree Handoff 的持久化检查点。
/// A persisted two-sided checkpoint for incremental Worktree Handoff.
class WorktreeHandoffCheckpoint {
  const WorktreeHandoffCheckpoint({
    required this.threadId,
    required this.worktreeId,
    required this.localPath,
    required this.worktreePath,
    required this.generation,
    required this.localSnapshot,
    required this.worktreeSnapshot,
  });

  final String threadId;
  final String worktreeId;
  final String localPath;
  final String worktreePath;
  final int generation;
  final Map<String, String> localSnapshot;
  final Map<String, String> worktreeSnapshot;

  factory WorktreeHandoffCheckpoint.fromJson(Map<Object?, Object?> json) {
    Map<String, String> snapshot(Object? value) => value is Map
        ? value.map((key, item) => MapEntry(key.toString(), item.toString()))
        : const {};

    return WorktreeHandoffCheckpoint(
      threadId: json['threadId']?.toString() ?? '',
      worktreeId: json['worktreeId']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      worktreePath: json['worktreePath']?.toString() ?? '',
      generation: int.tryParse('${json['generation']}') ?? 0,
      localSnapshot: snapshot(json['localSnapshot']),
      worktreeSnapshot: snapshot(json['worktreeSnapshot']),
    );
  }

  Map<String, Object?> toJson() => {
    'threadId': threadId,
    'worktreeId': worktreeId,
    'localPath': localPath,
    'worktreePath': worktreePath,
    'generation': generation,
    'localSnapshot': localSnapshot,
    'worktreeSnapshot': worktreeSnapshot,
  };
}
