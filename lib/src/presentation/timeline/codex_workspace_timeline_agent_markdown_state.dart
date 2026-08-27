// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_streaming_agent_text.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown_link_builder.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown_hard_break_builder.dart';

class AgentMarkdownState extends State<AgentMarkdown> {
  Map<String, WorkspaceFileReference?>? _resolvedLocalLinks;
  int _resolutionGeneration = 0;

  @visibleForTesting
  Future<void> resolveLocalLinksForTesting() => _resolveLocalLinks();

  @visibleForTesting
  int? get resolvedLocalLinkCountForTesting => _resolvedLocalLinks?.length;

  @override
  void initState() {
    super.initState();
    _prepareLocalLinks();
  }

  @override
  void didUpdateWidget(covariant AgentMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.workspacePath != widget.workspacePath) {
      _prepareLocalLinks();
    }
  }

  void _prepareLocalLinks() {
    unawaited(_resolveLocalLinks());
  }

  Future<void> _resolveLocalLinks() async {
    final workspacePath = widget.workspacePath;
    final hrefs = localMarkdownLinkHrefs(widget.data);
    final generation = ++_resolutionGeneration;
    if (workspacePath == null || hrefs.isEmpty) {
      _resolvedLocalLinks = const {};
      return;
    }
    _resolvedLocalLinks = null;
    final entries = await Future.wait(
      hrefs.map((href) async {
        WorkspaceFileReference? reference;
        try {
          reference = await resolveWorkspaceFileReference(
            href: href,
            workspacePath: workspacePath,
          );
        } catch (_) {
          // Rendering must not remain in its stable-text preflight state when
          // one malformed path or unavailable volume fails. The destination
          // remains an ordinary Markdown link and is revalidated if tapped.
          reference = null;
        }
        return MapEntry(href, reference);
      }),
    );
    if (!mounted ||
        generation != _resolutionGeneration ||
        workspacePath != widget.workspacePath) {
      return;
    }
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    final followedLatest =
        position != null && position.hasPixels && position.extentAfter <= 48;
    final previousPixels = position?.pixels;
    final previousMaximum = position?.maxScrollExtent;
    setState(() => _resolvedLocalLinks = Map.fromEntries(entries));
    if (!widget.preserveViewportOnResolve &&
        followedLatest &&
        previousPixels != null &&
        previousMaximum != null) {
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
    // Keep the exact streaming metrics until every local destination in this
    // reply is known. Rendering pending Markdown first and replacing each
    // text link with a file row later creates a second visible reflow at item
    // completion; the final Markdown tree must appear only once.
    if (_resolvedLocalLinks == null) {
      return StreamingAgentText(widget.data);
    }
    final palette = YeknomPalette.of(context);
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.5);
    return SelectionArea(
      key: const Key('agent-markdown-selection'),
      child: MarkdownBody(
        key: const ValueKey('agent-markdown-links-resolved'),
        data: widget.data,
        selectable: false,
        builders: {
          'a': AgentMarkdownLinkBuilder(
            workspacePath: widget.workspacePath,
            resolvedLocalLinks: _resolvedLocalLinks,
          ),
          'br': AgentMarkdownHardBreakBuilder(),
        },
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: body,
          pPadding: EdgeInsets.zero,
          blockSpacing: 8,
          listIndent: 22,
          listBullet: body,
          a: body?.copyWith(
            color: palette.active,
            decoration: TextDecoration.underline,
            decorationColor: palette.active.withValues(alpha: 0.65),
          ),
          code: body?.copyWith(
            color: palette.trace,
            fontFamily: 'monospace',
            fontSize: 12,
            backgroundColor: palette.field,
          ),
          codeblockPadding: const EdgeInsets.all(12),
          codeblockDecoration: BoxDecoration(
            color: palette.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          blockquotePadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          blockquoteDecoration: BoxDecoration(
            color: palette.raised,
            border: Border(left: BorderSide(color: palette.active, width: 3)),
          ),
          tableBorder: TableBorder.all(color: palette.border),
          tableHead: body?.copyWith(fontWeight: FontWeight.w700),
          tableBody: body,
        ),
      ),
    );
  }
}
