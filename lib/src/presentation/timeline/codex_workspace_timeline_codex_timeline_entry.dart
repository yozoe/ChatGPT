// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_codex_timeline_entry_state.dart';

class CodexTimelineEntry extends StatefulWidget {
  const CodexTimelineEntry(
    this.entry, {
    required this.workspacePath,
    this.streaming = false,
    this.onOpenSubagent,
    super.key,
  });

  final TimelineEntry entry;
  final String? workspacePath;
  final bool streaming;
  final ValueChanged<TimelineEntry>? onOpenSubagent;

  @override
  State<CodexTimelineEntry> createState() => CodexTimelineEntryState();
}
