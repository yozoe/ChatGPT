// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class AgentTextLink extends StatelessWidget {
  const AgentTextLink({
    required this.href,
    required this.label,
    required this.nodes,
    required this.workspacePath,
    required this.style,
    required this.codeStyle,
  });

  final String href;
  final String label;
  final List<md.Node> nodes;
  final String? workspacePath;
  final TextStyle? style;
  final TextStyle? codeStyle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(
            openAgentMarkdownDestination(
              context,
              href: href,
              workspacePath: workspacePath,
            ),
          ),
          child: Text.rich(
            TextSpan(
              style: style,
              children: agentMarkdownLinkSpans(
                nodes.isEmpty ? <md.Node>[md.Text(label)] : nodes,
                style: style,
                codeStyle: codeStyle,
                workspacePath: workspacePath,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
