enum LocalWorktreeState {
  creating,
  ready,
  running,
  completed,
  failed,
  missing,
  foreign,
  removed,
}

class LocalWorktreeRecord {
  const LocalWorktreeRecord({
    required this.worktreeId,
    required this.projectId,
    required this.sourceRepository,
    required this.worktreePath,
    required this.baseCommit,
    required this.state,
    required this.createdAt,
    this.baseRef,
    this.gitCommonDirectory,
    this.ownershipNonce,
    this.ownershipMac,
    this.threadId,
    this.branch,
    this.lastUsedAt,
  });

  final String worktreeId;
  final String projectId;
  final String? threadId;
  final String sourceRepository;
  final String worktreePath;
  final String baseCommit;
  final String? baseRef;
  final String? gitCommonDirectory;
  final String? ownershipNonce;
  final String? ownershipMac;
  final String? branch;
  final LocalWorktreeState state;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  factory LocalWorktreeRecord.fromJson(Map<Object?, Object?> json) =>
      LocalWorktreeRecord(
        worktreeId: json['worktreeId'].toString(),
        projectId: json['projectId'].toString(),
        threadId: json['threadId']?.toString(),
        sourceRepository: json['sourceRepository'].toString(),
        worktreePath: json['worktreePath'].toString(),
        baseCommit: json['baseCommit'].toString(),
        baseRef: json['baseRef']?.toString(),
        gitCommonDirectory: json['gitCommonDirectory']?.toString(),
        ownershipNonce: json['ownershipNonce']?.toString(),
        ownershipMac: json['ownershipMac']?.toString(),
        branch: json['branch']?.toString(),
        state: LocalWorktreeState.values.firstWhere(
          (value) => value.name == json['state'],
          orElse: () => LocalWorktreeState.failed,
        ),
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        lastUsedAt: DateTime.tryParse(json['lastUsedAt']?.toString() ?? ''),
      );

  Map<String, Object?> toJson() => {
    'worktreeId': worktreeId,
    'projectId': projectId,
    if (threadId != null) 'threadId': threadId,
    'sourceRepository': sourceRepository,
    'worktreePath': worktreePath,
    'baseCommit': baseCommit,
    if (baseRef != null) 'baseRef': baseRef,
    if (gitCommonDirectory != null) 'gitCommonDirectory': gitCommonDirectory,
    if (ownershipNonce != null) 'ownershipNonce': ownershipNonce,
    if (ownershipMac != null) 'ownershipMac': ownershipMac,
    if (branch != null) 'branch': branch,
    'state': state.name,
    'createdAt': createdAt.toIso8601String(),
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
  };

  LocalWorktreeRecord copyWith({
    String? threadId,
    LocalWorktreeState? state,
    DateTime? lastUsedAt,
    String? ownershipNonce,
    String? ownershipMac,
    String? gitCommonDirectory,
  }) => LocalWorktreeRecord(
    worktreeId: worktreeId,
    projectId: projectId,
    threadId: threadId ?? this.threadId,
    sourceRepository: sourceRepository,
    worktreePath: worktreePath,
    baseCommit: baseCommit,
    baseRef: baseRef,
    gitCommonDirectory: gitCommonDirectory ?? this.gitCommonDirectory,
    ownershipNonce: ownershipNonce ?? this.ownershipNonce,
    ownershipMac: ownershipMac ?? this.ownershipMac,
    branch: branch,
    state: state ?? this.state,
    createdAt: createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
}
