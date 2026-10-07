/// 解析 App Server 的网络等待通知，并确认它属于哪一个运行中的回合。
///
/// This value object keeps protocol parsing and thread/turn attribution out of
/// the controller's timeline side effects. It deliberately does not decide
/// how the activity is rendered or persisted.
class CodexNetworkRetryEvent {
  const CodexNetworkRetryEvent({
    required this.threadId,
    required this.turnId,
    required this.isActiveTurn,
  });

  /// Parses an `error` notification that asks the App Server to retry.
  ///
  /// A notification is accepted only when it explicitly requests a retry and
  /// its turn ID matches the locally tracked turn for that thread. This keeps
  /// late notifications from a stopped or replaced task out of the timeline.
  static CodexNetworkRetryEvent? fromParams(
    Map<String, dynamic> params, {
    required bool isActiveTurn,
    required String? expectedTurnId,
  }) {
    if (params['willRetry'] != true) return null;
    final threadId = _text(params['threadId']);
    final turnId = _text(params['turnId']);
    if (threadId.isEmpty ||
        turnId.isEmpty ||
        expectedTurnId == null ||
        turnId != expectedTurnId) {
      return null;
    }
    return CodexNetworkRetryEvent(
      threadId: threadId,
      turnId: turnId,
      isActiveTurn: isActiveTurn,
    );
  }

  final String threadId;
  final String turnId;
  final bool isActiveTurn;

  static String _text(Object? value) => value?.toString().trim() ?? '';
}
