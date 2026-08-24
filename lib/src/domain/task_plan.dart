/// App Server 结构化计划中单一步骤的执行状态。
/// Execution state of one step in an App Server structured plan.
enum TaskPlanStepStatus { pending, inProgress, completed }

/// 描述 Codex 在当前 turn 中共享的一条结构化执行步骤。
/// Describes one structured execution step shared by Codex for the current turn.
class TaskPlanStep {
  const TaskPlanStep({required this.step, required this.status});

  final String step;
  final TaskPlanStepStatus status;

  /// 从 App Server 的计划条目读取步骤文本与执行状态。
  /// Reads step text and execution status from an App Server plan entry.
  factory TaskPlanStep.fromJson(Map<dynamic, dynamic> value) {
    final rawStatus = value['status']?.toString();
    final status = switch (rawStatus) {
      'inProgress' ||
      'in_progress' ||
      'in-progress' => TaskPlanStepStatus.inProgress,
      'completed' => TaskPlanStepStatus.completed,
      _ => TaskPlanStepStatus.pending,
    };
    return TaskPlanStep(
      step: value['step']?.toString().trim() ?? '',
      status: status,
    );
  }
}

/// 保存 App Server 为当前 turn 发布的结构化计划和可选说明。
/// Holds the structured plan and optional explanation published for the current turn.
class TaskPlan {
  const TaskPlan({required this.turnId, required this.steps, this.explanation});

  final String turnId;
  final String? explanation;
  final List<TaskPlanStep> steps;

  /// 返回界面应聚焦的步骤下标：优先进行中，其次首个待办，全部完成时返回最后一步。
  /// Returns the UI-focused step index: in-progress first, then pending, or the final step when complete.
  int get focusedStepIndex {
    final inProgress = steps.indexWhere(
      (step) => step.status == TaskPlanStepStatus.inProgress,
    );
    if (inProgress >= 0) return inProgress;
    final pending = steps.indexWhere(
      (step) => step.status == TaskPlanStepStatus.pending,
    );
    if (pending >= 0) return pending;
    return steps.isEmpty ? -1 : steps.length - 1;
  }

  /// 返回已完成步骤数量。
  /// Returns the number of completed steps.
  int get completedStepCount =>
      steps.where((step) => step.status == TaskPlanStepStatus.completed).length;

  /// 从 `turn/plan/updated` 通知解析计划；无有效步骤时返回 `null`。
  /// Parses a plan from a `turn/plan/updated` notification, returning `null` when no valid steps exist.
  static TaskPlan? fromNotification(Map<dynamic, dynamic> params) {
    final rawPlan = params['plan'];
    if (rawPlan is! Iterable) return null;
    final steps = rawPlan
        .whereType<Map>()
        .map(TaskPlanStep.fromJson)
        .where((step) => step.step.isNotEmpty)
        .toList(growable: false);
    if (steps.isEmpty) return null;
    final explanation = params['explanation']?.toString().trim();
    return TaskPlan(
      turnId: params['turnId']?.toString() ?? '',
      explanation: explanation == null || explanation.isEmpty
          ? null
          : explanation,
      steps: steps,
    );
  }
}
