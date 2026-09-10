/// Authoritative context-window accounting published by Codex App Server.
class CodexThreadTokenUsage {
  const CodexThreadTokenUsage({
    required this.threadId,
    required this.turnId,
    required this.usedTokens,
    required this.totalTokens,
    required this.maximumTokens,
  });

  final String threadId;
  final String turnId;

  /// Tokens in the most recent model context, not cumulative thread usage.
  final int usedTokens;

  /// Cumulative tokens reported for the complete thread.
  final int totalTokens;

  /// Model context window, or null when the runtime does not provide one.
  final int? maximumTokens;

  static CodexThreadTokenUsage? fromNotification(Map<dynamic, dynamic> params) {
    final threadId = params['threadId']?.toString().trim() ?? '';
    final turnId = params['turnId']?.toString().trim() ?? '';
    final tokenUsage = params['tokenUsage'];
    if (threadId.isEmpty || turnId.isEmpty || tokenUsage is! Map) return null;

    final last = tokenUsage['last'];
    final total = tokenUsage['total'];
    if (last is! Map || total is! Map) return null;
    final usedTokens = _nonNegativeInt(last['totalTokens']);
    final totalTokens = _nonNegativeInt(total['totalTokens']);
    if (usedTokens == null || totalTokens == null) return null;

    final rawMaximum = tokenUsage['modelContextWindow'];
    final parsedMaximum = rawMaximum == null ? null : _positiveInt(rawMaximum);
    if (rawMaximum != null && parsedMaximum == null) return null;
    return CodexThreadTokenUsage(
      threadId: threadId,
      turnId: turnId,
      usedTokens: usedTokens,
      totalTokens: totalTokens,
      maximumTokens: parsedMaximum,
    );
  }

  static int? _nonNegativeInt(Object? value) {
    if (value is! int || value < 0) return null;
    return value;
  }

  static int? _positiveInt(Object? value) {
    if (value is! int || value <= 0) return null;
    return value;
  }
}
