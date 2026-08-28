// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_codex_timeline_entry.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_timeline_entry_body.dart';

class CodexTimelineEntryState extends State<CodexTimelineEntry> {
  Widget? _cachedBody;
  bool _preserveViewportOnMarkdownResolve = false;

  @override
  void didUpdateWidget(covariant CodexTimelineEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streaming && !widget.streaming) {
      _preserveViewportOnMarkdownResolve = true;
    }
    if (!identical(oldWidget.entry, widget.entry) ||
        oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.streaming != widget.streaming ||
        oldWidget.onSubmitUserMessageEdit != widget.onSubmitUserMessageEdit) {
      _cachedBody = null;
    }
  }

  @override
  Widget build(BuildContext context) => _cachedBody ??= TimelineEntryBody(
    widget.entry,
    workspacePath: widget.workspacePath,
    streaming: widget.streaming,
    preserveViewportOnMarkdownResolve: _preserveViewportOnMarkdownResolve,
    onOpenSubagent: widget.onOpenSubagent == null
        ? null
        : () => widget.onOpenSubagent?.call(widget.entry),
    onSubmitUserMessageEdit: widget.onSubmitUserMessageEdit,
  );
}
