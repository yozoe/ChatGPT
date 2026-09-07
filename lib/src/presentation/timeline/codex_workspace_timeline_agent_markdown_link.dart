// Extracted class from codex_workspace_timeline.dart.
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown_link_state.dart';

class AgentMarkdownLink extends StatefulWidget {
  const AgentMarkdownLink({
    super.key,
    required this.href,
    required this.label,
    required this.nodes,
    required this.workspacePath,
    required this.resolutionDeferred,
    required this.resolvedReference,
    required this.resolutionComplete,
    required this.style,
    required this.codeStyle,
  });

  final String href;
  final String label;
  final List<md.Node> nodes;
  final String? workspacePath;
  final bool resolutionDeferred;
  final WorkspaceFileReference? resolvedReference;
  final bool resolutionComplete;
  final TextStyle? style;
  final TextStyle? codeStyle;

  @override
  State<AgentMarkdownLink> createState() => AgentMarkdownLinkState();
}
