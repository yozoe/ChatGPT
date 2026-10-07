import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_side_chat_panel_state.dart';
import 'package:flutter/material.dart';

/// Presents an ephemeral fork while leaving the parent conversation visible.
class SideChatPanel extends StatefulWidget {
  const SideChatPanel({
    super.key,
    required this.session,
    required this.onClose,
  });

  final CodexSideChatSession session;
  final VoidCallback onClose;

  @override
  State<SideChatPanel> createState() => SideChatPanelState();
}
