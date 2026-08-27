// Extracted class from task_plan.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'task_plan_support.dart';
import 'task_plan_task_plan_step.dart';

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
