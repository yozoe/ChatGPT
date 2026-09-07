// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown_state.dart';

class AgentMarkdown extends StatefulWidget {
  const AgentMarkdown(
    this.data, {
    super.key,
    required this.workspacePath,
    this.preserveViewportOnResolve = false,
  });

  final String data;
  final String? workspacePath;
  final bool preserveViewportOnResolve;

  @override
  State<AgentMarkdown> createState() => AgentMarkdownState();
}
