// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown_link.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_text_link.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_file_link.dart';

class AgentMarkdownLinkState extends State<AgentMarkdownLink> {
  WorkspaceFileReference? _reference;

  @visibleForTesting
  Future<void> resolveForTesting() => _resolve();

  @override
  void initState() {
    super.initState();
    _reference = widget.resolvedReference;
    if (widget.resolutionComplete || widget.resolutionDeferred) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolve());
    });
  }

  @override
  void didUpdateWidget(covariant AgentMarkdownLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resolutionComplete) {
      _reference = widget.resolvedReference;
      return;
    }
    if (oldWidget.href != widget.href ||
        oldWidget.workspacePath != widget.workspacePath) {
      _reference = null;
      if (!widget.resolutionDeferred) unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final workspacePath = widget.workspacePath;
    final href = widget.href;
    final reference = workspacePath == null || href.isEmpty
        ? null
        : await resolveWorkspaceFileReference(
            href: href,
            workspacePath: workspacePath,
          );
    if (!mounted ||
        workspacePath != widget.workspacePath ||
        href != widget.href) {
      return;
    }
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    final followedLatest =
        position != null && position.hasPixels && position.extentAfter <= 48;
    final previousPixels = position?.pixels;
    final previousMaximum = position?.maxScrollExtent;
    setState(() => _reference = reference);
    if (followedLatest && previousPixels != null && previousMaximum != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !position.hasPixels ||
            (position.pixels - previousPixels).abs() > 0.5 ||
            (position.maxScrollExtent - previousMaximum).abs() <= 0.5) {
          return;
        }
        position.jumpTo(position.maxScrollExtent);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = _reference;
    if (reference != null) {
      return AgentFileLink(
        href: widget.href,
        reference: reference,
        workspacePath: widget.workspacePath!,
      );
    }
    return AgentTextLink(
      href: widget.href,
      label: widget.label,
      nodes: widget.nodes,
      workspacePath: widget.workspacePath,
      style: widget.style,
      codeStyle: widget.codeStyle,
    );
  }
}
