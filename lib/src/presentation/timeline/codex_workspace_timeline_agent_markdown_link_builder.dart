// Extracted class from codex_workspace_timeline.dart.
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
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
