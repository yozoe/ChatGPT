// Shared declarations extracted from task_plan.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
/// App Server 结构化计划中单一步骤的执行状态。
/// Execution state of one step in an App Server structured plan.
enum TaskPlanStepStatus { pending, inProgress, completed }

/// 描述 Codex 在当前 turn 中共享的一条结构化执行步骤。
/// Describes one structured execution step shared by Codex for the current turn.

/// 保存 App Server 为当前 turn 发布的结构化计划和可选说明。
/// Holds the structured plan and optional explanation published for the current turn.
