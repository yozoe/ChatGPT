import 'package:chatgpt/src/domain/codex_thread_goal.dart';
import 'package:chatgpt/src/domain/pending_plan_implementation_request.dart';
import 'package:chatgpt/src/domain/task_plan.dart';

/// 集中维护控制器使用的可变 Goal 与 Plan 集合。
/// Owns the mutable Goal and Plan collections used by the controller.
///
/// 控制器继续协调 App Server 请求、持久化与时间线更新；本类型仅归组线程
/// Goal 生命周期和 Plan 模式实现交接所需的状态。
/// The controller continues to coordinate App Server requests, persistence,
/// and timeline updates. This type only groups state for a thread's Goal
/// lifecycle or a Plan-mode implementation hand-off.
class CodexGoalPlanState {
  TaskPlan? activeTaskPlan;
  final Map<String, CodexThreadGoal> threadGoalsById =
      <String, CodexThreadGoal>{};
  final Map<String, int> threadGoalRevisions = <String, int>{};
  final Map<String, String> lastGoalTimelineStatusByThread = <String, String>{};
  final Set<String> goalContinuationPendingThreadIds = <String>{};
  final Set<String> goalContinuationAwaitingAcceptanceThreadIds = <String>{};
  final Set<String> automaticGoalTurnThreadIds = <String>{};
  final Set<String> goalTurnsWithToolCalls = <String>{};
  final Set<String> goalContinuationSuppressedThreadIds = <String>{};
  final Set<String> goalPauseRequestedThreadIds = <String>{};
  final Map<String, String> goalContinuationErrorsByThread = <String, String>{};
  final Set<String> goalOperationThreadIds = <String>{};
  final Map<String, String> goalOperationErrorsByThread = <String, String>{};

  final Map<String, bool> planModeByThreadId = <String, bool>{};
  bool newThreadPlanMode = false;
  final Map<String, PendingPlanImplementationRequest>
  planImplementationCandidates = <String, PendingPlanImplementationRequest>{};
  final Map<String, PendingPlanImplementationRequest>
  pendingPlanImplementations = <String, PendingPlanImplementationRequest>{};
  final Set<String> successfulPlanTurnKeys = <String>{};
  final Set<String> rejectedPlanTurnKeys = <String>{};
  final Set<String> handledPlanImplementationKeys = <String>{};

  /// 清理临时 Goal 续接状态，同时保留权威线程目标快照。
  /// Clears transient Goal continuation state while preserving thread goals.
  void clearGoalContinuationState() {
    goalContinuationPendingThreadIds.clear();
    goalContinuationAwaitingAcceptanceThreadIds.clear();
    automaticGoalTurnThreadIds.clear();
    goalTurnsWithToolCalls.clear();
    goalContinuationSuppressedThreadIds.clear();
    goalPauseRequestedThreadIds.clear();
    goalContinuationErrorsByThread.clear();
  }

  /// 清理 Plan 完成后的实现交接记录，不改变线程的模式选择。
  /// Clears Plan implementation hand-offs without changing mode selections.
  void clearPlanImplementationState() {
    planImplementationCandidates.clear();
    pendingPlanImplementations.clear();
    successfulPlanTurnKeys.clear();
    rejectedPlanTurnKeys.clear();
    handledPlanImplementationKeys.clear();
  }

  /// 将所有 Goal 与 Plan 状态恢复为新控制器的初始值。
  /// Resets all Goal and Plan state to a new controller's initial values.
  void clear() {
    activeTaskPlan = null;
    threadGoalsById.clear();
    threadGoalRevisions.clear();
    lastGoalTimelineStatusByThread.clear();
    goalOperationThreadIds.clear();
    goalOperationErrorsByThread.clear();
    clearGoalContinuationState();
    planModeByThreadId.clear();
    newThreadPlanMode = false;
    clearPlanImplementationState();
  }
}
