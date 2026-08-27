// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_task_plan_status_mark.dart';

class TaskPlanStepRow extends StatelessWidget {
  const TaskPlanStepRow({required this.step, required this.focused, super.key});

  final TaskPlanStep step;
  final bool focused;

  /// 构建单条计划步骤，并以文字语义和图形共同表达状态。
  /// Builds one plan step, expressing status through both semantics and visuals.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final statusLabel = switch (step.status) {
      TaskPlanStepStatus.pending => '待执行',
      TaskPlanStepStatus.inProgress => '进行中',
      TaskPlanStepStatus.completed => '已完成',
    };
    return Semantics(
      label: '$statusLabel：${step.step}',
      child: Container(
        color: focused
            ? palette.active.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: TaskPlanStatusMark(status: step.status, active: focused),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                step.step,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: step.status == TaskPlanStepStatus.completed
                      ? palette.muted
                      : palette.trace,
                  fontWeight: focused ? FontWeight.w600 : FontWeight.w400,
                  decoration: step.status == TaskPlanStepStatus.completed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
