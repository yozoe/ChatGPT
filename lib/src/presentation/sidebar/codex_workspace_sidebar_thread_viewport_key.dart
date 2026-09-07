// Extracted class from codex_workspace_sidebar.dart.

class ThreadViewportKey {
  const ThreadViewportKey({required this.workspace, required this.threadId});

  final String? workspace;
  final String? threadId;

  String get storageKey =>
      '${workspace ?? 'no-workspace'}:${threadId ?? 'draft'}';

  @override
  bool operator ==(Object other) =>
      other is ThreadViewportKey &&
      workspace == other.workspace &&
      threadId == other.threadId;

  @override
  int get hashCode => Object.hash(workspace, threadId);
}
