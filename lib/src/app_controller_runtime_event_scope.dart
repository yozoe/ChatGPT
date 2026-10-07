/// Reads thread and turn identity from App Server event payloads.
///
/// Compatible servers may place identifiers on the event envelope or inside
/// its nested `turn` object. This parser preserves the controller's existing
/// direct-field precedence without making any routing or lifecycle decision.
class CodexRuntimeEventScope {
  const CodexRuntimeEventScope._();

  static String? threadIdFromParams(Map<String, dynamic> params) {
    final direct = _text(params['threadId']);
    if (direct.isNotEmpty) return direct;
    final turn = params['turn'];
    final nested = turn is Map ? _text(turn['threadId']) : '';
    return nested.isEmpty ? null : nested;
  }

  static String? turnIdFromParams(Map<String, dynamic> params) {
    final direct = _text(params['turnId']);
    if (direct.isNotEmpty) return direct;
    final turn = params['turn'];
    final nested = turn is Map ? _text(turn['id']) : '';
    return nested.isEmpty ? null : nested;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}
