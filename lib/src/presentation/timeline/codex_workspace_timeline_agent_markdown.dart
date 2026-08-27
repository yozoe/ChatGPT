// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_markdown_state.dart';

class AgentMarkdown extends StatefulWidget {
  const AgentMarkdown(
    this.data, {
    required this.workspacePath,
    this.preserveViewportOnResolve = false,
  });

  final String data;
  final String? workspacePath;
  final bool preserveViewportOnResolve;

  @override
  State<AgentMarkdown> createState() => AgentMarkdownState();
}
