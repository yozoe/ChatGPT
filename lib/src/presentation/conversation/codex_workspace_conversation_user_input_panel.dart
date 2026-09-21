import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_input_panel_state.dart';

/// Displays the structured questions emitted by Codex during Plan mode.
class UserInputPanel extends StatefulWidget {
  const UserInputPanel({
    super.key,
    required this.request,
    required this.taskLabel,
    required this.enabled,
    this.autoResolutionDeadline,
    required this.onSubmit,
    required this.onDismiss,
    this.onUserInteraction,
    this.initiallySelectFirstOption = true,
    this.otherLabel = '其他',
    this.otherDescription = '输入其他回答',
    this.textFieldHint = '输入回答',
  });

  final PendingUserInputRequest request;
  final String? taskLabel;
  final bool enabled;
  final DateTime? autoResolutionDeadline;
  final Future<void> Function(
    JsonMap answers,
    List<PendingUserInputAnswer> answerDetails,
  )
  onSubmit;
  final Future<void> Function() onDismiss;
  final VoidCallback? onUserInteraction;
  final bool initiallySelectFirstOption;
  final String otherLabel;
  final String otherDescription;
  final String textFieldHint;

  @override
  State<UserInputPanel> createState() => UserInputPanelState();
}
