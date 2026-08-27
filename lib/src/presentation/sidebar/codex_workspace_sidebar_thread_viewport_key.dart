// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';

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
