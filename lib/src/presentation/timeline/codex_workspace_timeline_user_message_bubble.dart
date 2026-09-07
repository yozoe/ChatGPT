// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_user_message_bubble_state.dart';

class UserMessageBubble extends StatefulWidget {
  const UserMessageBubble({super.key, required this.entry, this.onSubmitEdit});

  final TimelineEntry entry;
  final Future<bool> Function(TimelineEntry entry, String text)? onSubmitEdit;

  @override
  State<UserMessageBubble> createState() => UserMessageBubbleState();
}
