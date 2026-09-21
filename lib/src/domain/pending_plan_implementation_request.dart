/// A completed Plan-mode turn awaiting implementation, feedback, or dismissal.
class PendingPlanImplementationRequest {
  const PendingPlanImplementationRequest({
    required this.threadId,
    required this.turnId,
    required this.planContent,
  });

  final String threadId;
  final String turnId;
  final String planContent;

  String get requestKey => '$threadId:$turnId';
}
