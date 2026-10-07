import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_failed_turn_kind_classifier.dart';
import 'package:chatgpt/src/app_controller_failed_turn_retry.dart';
import 'package:chatgpt/src/services/codex_app_server_exception.dart';

void main() {
  test('prioritizes usage limits over capacity identifiers', () {
    expect(
      CodexFailedTurnKindClassifier.classify({
        'error': {'code': 'usage_limit_reached', 'type': 'model_at_capacity'},
      }, 'temporary capacity response'),
      FailedTurnKind.usageLimit,
    );
  });

  test('classifies structured App Server exceptions and numeric 429s', () {
    expect(
      CodexFailedTurnKindClassifier.classify(
        const CodexAppServerException(
          message: 'request rejected',
          code: 'rate_limit_exceeded',
        ),
        'request rejected',
      ),
      FailedTurnKind.capacityRateLimit,
    );
    expect(
      CodexFailedTurnKindClassifier.classify({'code': 429}, 'request failed'),
      FailedTurnKind.capacityRateLimit,
    );
  });

  test('uses retryable as the safe fallback', () {
    expect(
      CodexFailedTurnKindClassifier.classify({
        'message': 'filesystem unavailable',
      }, 'filesystem unavailable'),
      FailedTurnKind.retryable,
    );
  });
}
