// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_linked_image_state.dart';

class AgentLinkedImage extends StatefulWidget {
  const AgentLinkedImage({
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
