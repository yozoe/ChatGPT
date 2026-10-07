/// Stores streamed reasoning-summary fragments for the active turn.
///
/// The controller remains responsible for deciding whether an event belongs to
/// the active turn and for presenting the cleaned summary. This type only owns
/// the mutable, per-item fragment collection and its lifecycle.
class CodexReasoningSummaryState {
  final Map<String, Map<int, String>> partsByItem =
      <String, Map<int, String>>{};

  CodexReasoningSummaryState clone() {
    return CodexReasoningSummaryState()
      ..partsByItem.addAll({
        for (final entry in partsByItem.entries)
          entry.key: Map<int, String>.of(entry.value),
      });
  }

  void ensurePart(String itemId, int summaryIndex) {
    partsByItem
        .putIfAbsent(itemId, () => <int, String>{})
        .putIfAbsent(summaryIndex, () => '');
  }

  String appendDelta(String itemId, int summaryIndex, String delta) {
    final parts = partsByItem.putIfAbsent(itemId, () => <int, String>{});
    parts[summaryIndex] = '${parts[summaryIndex] ?? ''}$delta';
    return parts[summaryIndex]!;
  }

  void removeItem(String itemId) {
    partsByItem.remove(itemId);
  }

  void clear() {
    partsByItem.clear();
  }
}
