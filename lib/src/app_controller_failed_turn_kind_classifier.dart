import 'package:chatgpt/src/services/codex_app_server_exception.dart';

import 'app_controller_failed_turn_retry.dart';

/// Classifies a failed turn without reading or mutating controller state.
///
/// The controller remains responsible for deciding what to do with the kind
/// (for example, whether to schedule an automatic retry). Keeping this parser
/// pure makes the protocol boundary independently testable and preserves the
/// existing precedence of usage-limit errors over capacity errors.
class CodexFailedTurnKindClassifier {
  const CodexFailedTurnKindClassifier._();

  static FailedTurnKind classify(Object? error, String message) {
    final identifiers = <String>[];
    _collectIdentifiers(
      error is CodexAppServerException
          ? {'code': error.code, 'type': error.type}
          : error,
      identifiers,
    );
    final identifier = identifiers
        .join(' ')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedMessage = message.trim().toLowerCase();
    final isUsageLimit =
        identifier.contains('usagelimit') ||
        identifier.contains('quotaexceeded') ||
        identifier.contains('insufficientquota') ||
        normalizedMessage.contains('usage limit') ||
        normalizedMessage.contains('exceeded your current quota') ||
        normalizedMessage == 'quota exceeded';
    if (isUsageLimit) return FailedTurnKind.usageLimit;
    if (identifier == '429' ||
        identifier.contains('ratelimit') ||
        identifier.contains('toomanyrequests') ||
        identifier.contains('modelatcapacity') ||
        identifier.contains('capacity') ||
        normalizedMessage.contains('selected model is at capacity') ||
        normalizedMessage.contains('model is at capacity') ||
        normalizedMessage.contains('rate limit') ||
        normalizedMessage.contains('too many requests') ||
        normalizedMessage.contains('http 429') ||
        normalizedMessage == '429') {
      return FailedTurnKind.capacityRateLimit;
    }
    return FailedTurnKind.retryable;
  }

  static void _collectIdentifiers(Object? value, List<String> identifiers) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key == 'code' ||
            key == 'type' ||
            key == 'ratelimitreachedtype' ||
            key == 'error') {
          _collectIdentifiers(entry.value, identifiers);
        }
      }
    } else if (value != null) {
      identifiers.add(value.toString());
    }
  }
}
