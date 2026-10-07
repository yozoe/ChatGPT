import 'dart:collection';

import 'app_controller_live_turn_activity.dart';
import 'app_controller_reasoning_summary_state.dart';

/// Holds transient App Server activity state for the currently visible turn.
class CodexTurnActivityState {
  String? activeCommand;
  String? activeCommandItemId;
  LiveTurnActivity? activeActivity;
  final LinkedHashMap<String, LiveTurnActivity> collaborationActivities =
      LinkedHashMap<String, LiveTurnActivity>();
  final CodexReasoningSummaryState reasoningSummary =
      CodexReasoningSummaryState();
  final Set<String> completedCommandItemIds = <String>{};
  final Set<String> completedPlanItemIds = <String>{};

  /// Compatibility view for existing controller and test callers.
  Map<String, Map<int, String>> get reasoningSummaryParts =>
      reasoningSummary.partsByItem;

  CodexTurnActivityState clone() {
    return CodexTurnActivityState()
      ..activeCommand = activeCommand
      ..activeCommandItemId = activeCommandItemId
      ..activeActivity = activeActivity
      ..collaborationActivities.addAll(collaborationActivities)
      ..reasoningSummary.partsByItem.addAll(
        reasoningSummary.clone().partsByItem,
      )
      ..completedCommandItemIds.addAll(completedCommandItemIds)
      ..completedPlanItemIds.addAll(completedPlanItemIds);
  }

  void clear() {
    activeCommand = null;
    activeCommandItemId = null;
    activeActivity = null;
    collaborationActivities.clear();
    reasoningSummary.clear();
    completedCommandItemIds.clear();
    completedPlanItemIds.clear();
  }
}
