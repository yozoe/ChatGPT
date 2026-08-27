// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown_link.dart';

class AgentMarkdownLinkBuilder extends MarkdownElementBuilder {
  AgentMarkdownLinkBuilder({
    required this.workspacePath,
    required this.resolvedLocalLinks,
  });

  final String? workspacePath;
  final Map<String, WorkspaceFileReference?>? resolvedLocalLinks;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'] ?? '';
    final palette = YeknomPalette.of(context);
    final linkStyle = preferredStyle ?? parentStyle;
    return AgentMarkdownLink(
      href: href,
      label: agentMarkdownLinkLabel(element, href),
      nodes: element.children ?? const <md.Node>[],
      workspacePath: workspacePath,
      resolutionDeferred:
          isPotentialLocalMarkdownHref(href) && resolvedLocalLinks == null,
      resolvedReference: resolvedLocalLinks?[href],
      resolutionComplete:
          !isPotentialLocalMarkdownHref(href) ||
          (resolvedLocalLinks?.containsKey(href) ?? false),
      style: linkStyle,
      codeStyle: linkStyle?.copyWith(
        color: palette.trace,
        fontFamily: 'monospace',
        fontSize: 12,
        backgroundColor: palette.field,
      ),
    );
  }
}
