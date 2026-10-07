import 'app_controller_support.dart';

/// Parses terminal turn payloads without performing lifecycle side effects.
///
/// The controller owns completion routing and persistence; this parser only
/// reads the protocol status and maps it to the existing public outcome enum.
class CodexTurnCompletionParser {
  const CodexTurnCompletionParser._();

  static String statusFromParams(Map<String, dynamic> params) {
    final turn = params['turn'];
    final turnMap = turn is Map
        ? Map<String, dynamic>.from(turn)
        : const <String, dynamic>{};
    return turnMap['status']?.toString() ?? params['status']?.toString() ?? '';
  }

  static TurnCompletionOutcome outcomeFromStatus(String? status) {
    final normalized = status?.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    return switch (normalized) {
      'completed' ||
      'complete' ||
      'done' ||
      'success' ||
      'succeeded' ||
      'idle' => TurnCompletionOutcome.succeeded,
      'interrupted' ||
      'cancelled' ||
      'canceled' => TurnCompletionOutcome.stopped,
      'failed' ||
      'failure' ||
      'error' ||
      'errored' ||
      'systemerror' => TurnCompletionOutcome.failed,
      _ => TurnCompletionOutcome.unknown,
    };
  }
}
