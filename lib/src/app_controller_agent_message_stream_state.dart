/// Holds the mutable state needed to merge one turn's streamed Agent messages.
///
/// The controller still owns timeline entries and notifications; this type
/// only owns item identity, phase, deduplication, and index bookkeeping.
class CodexAgentMessageStreamState {
  final Map<String, int> entryIndexByItem = <String, int>{};
  final Map<String, String> phaseByItem = <String, String>{};
  final Set<String> completedItemIds = <String>{};
  String? activeItemId;

  CodexAgentMessageStreamState clone() {
    return CodexAgentMessageStreamState()
      ..entryIndexByItem.addAll(entryIndexByItem)
      ..phaseByItem.addAll(phaseByItem)
      ..completedItemIds.addAll(completedItemIds)
      ..activeItemId = activeItemId;
  }

  void restoreFrom(CodexAgentMessageStreamState other) {
    entryIndexByItem
      ..clear()
      ..addAll(other.entryIndexByItem);
    phaseByItem
      ..clear()
      ..addAll(other.phaseByItem);
    completedItemIds
      ..clear()
      ..addAll(other.completedItemIds);
    activeItemId = other.activeItemId;
  }

  void shiftEntryIndexes(int insertionIndex) {
    entryIndexByItem.updateAll(
      (_, index) => index >= insertionIndex ? index + 1 : index,
    );
  }

  void clear() {
    entryIndexByItem.clear();
    phaseByItem.clear();
    completedItemIds.clear();
    activeItemId = null;
  }
}
