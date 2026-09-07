// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail_state.dart';

/// A fixed Codex-style index containing one mark per sent user message.
class ConversationUserMessageRail extends StatefulWidget {
  const ConversationUserMessageRail({
    required this.messages,
    required this.onMessageSelected,
    super.key,
  });

  final List<TimelineEntry> messages;
  final Future<void> Function(String messageId) onMessageSelected;

  @override
  State<ConversationUserMessageRail> createState() =>
      ConversationUserMessageRailState();
}
