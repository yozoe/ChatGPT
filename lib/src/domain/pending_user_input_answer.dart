/// Preserves whether a structured answer came from an option or free-form text.
class PendingUserInputAnswer {
  const PendingUserInputAnswer({
    required this.questionId,
    this.selectedOptionId,
    this.freeformText,
  });

  final String questionId;
  final String? selectedOptionId;
  final String? freeformText;
}
