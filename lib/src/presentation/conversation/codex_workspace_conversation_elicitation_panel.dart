// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_elicitation_panel_state.dart';

class ElicitationPanel extends StatefulWidget {
  const ElicitationPanel({
    super.key,
    required this.elicitation,
    required this.taskLabel,
    required this.enabled,
    required this.onRespond,
  });

  final PendingElicitation elicitation;
  final String? taskLabel;
  final bool enabled;
  final Future<void> Function({required String action, JsonMap? content})
  onRespond;

  @override
  State<ElicitationPanel> createState() => ElicitationPanelState();
}
