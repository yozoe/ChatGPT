// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_linked_image_state.dart';

class AgentLinkedImage extends StatefulWidget {
  const AgentLinkedImage({
    super.key,
    required this.source,
    required this.alt,
    required this.workspacePath,
    required this.fallbackStyle,
  });

  final String source;
  final String alt;
  final String? workspacePath;
  final TextStyle? fallbackStyle;

  @override
  State<AgentLinkedImage> createState() => AgentLinkedImageState();
}
