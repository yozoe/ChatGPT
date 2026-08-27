// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_submission.dart';

class ComposerPanel extends StatefulWidget {
  const ComposerPanel({
    super.key,
    required this.controller,
    required this.composer,
    required this.recordSkillRequest,
    required this.onSend,
    required this.onQueueSteer,
  });

  final CodexController controller;
  final TextEditingController composer;
  final ValueListenable<int> recordSkillRequest;
  final Future<bool> Function(ComposerSubmission submission) onSend;
  final Future<bool> Function(ComposerSubmission submission) onQueueSteer;

  @override
  State<ComposerPanel> createState() => ComposerPanelState();
}
