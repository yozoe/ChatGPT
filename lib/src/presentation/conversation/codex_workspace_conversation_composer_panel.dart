// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
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
    this.onOpenSideChat,
    this.sideChatEnabled = true,
  });

  final CodexController controller;
  final TextEditingController composer;
  final ValueListenable<int> recordSkillRequest;
  final Future<bool> Function(ComposerSubmission submission) onSend;
  final Future<bool> Function(ComposerSubmission submission) onQueueSteer;
  final Future<void> Function()? onOpenSideChat;
  final bool sideChatEnabled;

  @override
  State<ComposerPanel> createState() => ComposerPanelState();
}
