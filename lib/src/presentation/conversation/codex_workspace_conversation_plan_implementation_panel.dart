import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_input_panel.dart';

/// Presents the official completed-plan implementation or feedback choice.
class PlanImplementationPanel extends StatelessWidget {
  const PlanImplementationPanel({
    super.key,
    required this.request,
    required this.enabled,
    required this.onImplement,
    required this.onFeedback,
    required this.onDismiss,
  });

  static const implementOption = 'Yes, implement this plan';
  static const questionId = 'implement-plan';

  final PendingPlanImplementationRequest request;
  final bool enabled;
  final Future<void> Function() onImplement;
  final Future<void> Function(String feedback) onFeedback;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    final inputRequest = PendingUserInputRequest(
      requestId: request.requestKey,
      params: const {},
      threadId: request.threadId,
      turnId: request.turnId,
      itemId: questionId,
      questions: const [
        PendingUserInputQuestion(
          id: questionId,
          header: 'Implement this plan?',
          question: 'Implement this plan?',
          options: [
            PendingUserInputOption(label: implementOption, description: ''),
          ],
          allowsOther: true,
          isSecret: false,
        ),
      ],
      isBlocking: false,
    );
    return UserInputPanel(
      request: inputRequest,
      taskLabel: null,
      enabled: enabled,
      initiallySelectFirstOption: false,
      otherLabel: 'Other',
      otherDescription: 'Give feedback',
      textFieldHint: 'Tell Codex what to change',
      onSubmit: (_, answerDetails) async {
        final answer = answerDetails.firstOrNull;
        if (answer?.selectedOptionId == implementOption) {
          await onImplement();
        } else if (answer?.freeformText case final feedback?
            when feedback.isNotEmpty) {
          await onFeedback(feedback);
        }
      },
      onDismiss: onDismiss,
    );
  }
}
