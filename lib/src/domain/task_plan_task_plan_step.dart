// Extracted class from task_plan.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'task_plan_support.dart';

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
