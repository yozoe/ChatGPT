/// 一个可重复打开的 Codex Desk 工作区，由主目录和仅用于新任务的附加目录组成。
/// A reopenable Codex Desk workspace composed of one primary directory and additional roots for new tasks.
class WorkspaceConfiguration {
  WorkspaceConfiguration({
    required this.primaryPath,
    List<String> additionalPaths = const [],
    this.name,
    String? id,
  }) : id = id?.trim().isNotEmpty == true ? id!.trim() : null,
       additionalPaths = List.unmodifiable(additionalPaths);

  /// Stable identity for the Codex Desk project. It is deliberately separate
  /// from the source directory so project history does not leak by path.
  final String? id;
  final String primaryPath;
  final List<String> additionalPaths;
  final String? name;

  /// 从持久化 JSON 中读取工作区；无效主目录会由调用方忽略。
  /// Reads a persisted workspace from JSON; callers discard entries with invalid primary paths.
  factory WorkspaceConfiguration.fromJson(Map<Object?, Object?> json) {
    final primaryPath = json['primaryPath']?.toString().trim() ?? '';
    final additional = json['additionalPaths'];
    final name = json['name']?.toString().trim();
    return WorkspaceConfiguration(
      primaryPath: primaryPath,
      id: json['id']?.toString(),
      name: name == null || name.isEmpty ? null : name,
      additionalPaths: additional is Iterable
          ? additional
                .whereType<String>()
                .map((path) => path.trim())
                .where((path) => path.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }

  /// 返回工作区的稳定 JSON 表示，不保存项目文件或对话内容。
  /// Returns a stable workspace JSON representation without project files or conversation content.
  Map<String, Object?> toJson() => {
    if (id != null && id!.isNotEmpty) 'id': id,
    'primaryPath': primaryPath,
    'additionalPaths': additionalPaths,
    if (name != null && name!.isNotEmpty) 'name': name,
  };
}
