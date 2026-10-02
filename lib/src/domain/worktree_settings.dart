import 'dart:io';

class WorktreeSettings {
  const WorktreeSettings({
    required this.rootPath,
    this.fetchBeforeCreate = false,
    this.autoCleanup = true,
    this.retentionLimit = 15,
  });

  factory WorktreeSettings.defaults() {
    final home = Platform.environment['HOME']?.trim();
    return WorktreeSettings(
      rootPath: home == null || home.isEmpty
          ? '.codex/worktrees'
          : '$home/.codex/worktrees',
    );
  }

  factory WorktreeSettings.fromJson(Map<Object?, Object?> json) {
    final defaults = WorktreeSettings.defaults();
    final root = json['rootPath']?.toString().trim();
    final limit =
        int.tryParse('${json['retentionLimit']}') ?? defaults.retentionLimit;
    return WorktreeSettings(
      rootPath: root == null || root.isEmpty ? defaults.rootPath : root,
      fetchBeforeCreate: json['fetchBeforeCreate'] == true,
      autoCleanup: json['autoCleanup'] != false,
      retentionLimit: limit < 1 ? defaults.retentionLimit : limit,
    );
  }

  final String rootPath;
  final bool fetchBeforeCreate;
  final bool autoCleanup;
  final int retentionLimit;

  Map<String, Object?> toJson() => {
    'rootPath': rootPath,
    'fetchBeforeCreate': fetchBeforeCreate,
    'autoCleanup': autoCleanup,
    'retentionLimit': retentionLimit,
  };

  WorktreeSettings copyWith({
    String? rootPath,
    bool? fetchBeforeCreate,
    bool? autoCleanup,
    int? retentionLimit,
  }) => WorktreeSettings(
    rootPath: rootPath ?? this.rootPath,
    fetchBeforeCreate: fetchBeforeCreate ?? this.fetchBeforeCreate,
    autoCleanup: autoCleanup ?? this.autoCleanup,
    retentionLimit: retentionLimit ?? this.retentionLimit,
  );
}
