// Extracted class from app_controller.dart.
import 'app_controller_turn_submission.dart';

/// 可在任务失败后原样再次提交的 turn 输入及错误信息。
/// Exact turn input and error retained for retry after a task failure.
class FailedTurnRetry {
  const FailedTurnRetry({
    required this.submission,
    required this.error,
    this.kind = FailedTurnKind.retryable,
  });

  final TurnSubmission submission;
  final String error;
  final FailedTurnKind kind;
}

enum FailedTurnKind { retryable, usageLimit }
