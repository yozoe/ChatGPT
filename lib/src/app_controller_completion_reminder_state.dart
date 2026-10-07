/// 集中维护完成提醒、Dock 徽标和完成事件去重状态。
/// Owns completion reminders, Dock badges, and completion-event deduplication state.
///
/// 控制器仍负责把完成事件写入历史、发送系统通知和按工作区持久化；本类型
/// 只归组提醒集合与去重键，确保前台、后台和旧协议事件共用同一边界。
/// The controller still persists completion events, sends notifications, and
/// writes workspace history; this type only groups reminder sets and dedup keys
/// shared by foreground, background, and legacy events.
class CodexCompletionReminderState {
  final Set<String> acknowledgedThreadIds = <String>{};
  final Set<String> unacknowledgedThreadIds = <String>{};
  final Set<String> notifiedCompletionKeys = <String>{};
  final Set<String> handledTurnCompletionKeys = <String>{};

  void clearSessionReminders() {
    unacknowledgedThreadIds.clear();
    notifiedCompletionKeys.clear();
    handledTurnCompletionKeys.clear();
  }

  void clear() {
    acknowledgedThreadIds.clear();
    clearSessionReminders();
  }
}
