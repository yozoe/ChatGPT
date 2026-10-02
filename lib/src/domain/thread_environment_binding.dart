enum ThreadEnvironmentKind { local, managedWorktree }

class ThreadEnvironmentBinding {
  const ThreadEnvironmentBinding({
    required this.threadId,
    required this.kind,
    required this.workingDirectory,
    this.worktreeId,
  });

  final String threadId;
  final ThreadEnvironmentKind kind;
  final String workingDirectory;
  final String? worktreeId;

  factory ThreadEnvironmentBinding.fromJson(Map<Object?, Object?> json) =>
      ThreadEnvironmentBinding(
        threadId: json['threadId'].toString(),
        kind: ThreadEnvironmentKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => ThreadEnvironmentKind.local,
        ),
        workingDirectory: json['workingDirectory'].toString(),
        worktreeId: json['worktreeId']?.toString(),
      );

  Map<String, Object?> toJson() => {
    'threadId': threadId,
    'kind': kind.name,
    'workingDirectory': workingDirectory,
    if (worktreeId != null) 'worktreeId': worktreeId,
  };
}
