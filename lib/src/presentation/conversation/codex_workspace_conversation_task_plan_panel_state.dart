// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_task_plan_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_task_plan_step_row.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_task_plan_status_mark.dart';

class TaskPlanPanelState extends State<TaskPlanPanel> {
  late List<GlobalKey> _stepKeys;

  TaskPlan get plan => widget.plan;

  /// 初始化步骤锚点，并在首帧把当前步骤滚入可见区域。
  /// Initializes step anchors and scrolls the current step into view after the first frame.
  @override
  void initState() {
    super.initState();
    _stepKeys = List.generate(plan.steps.length, (_) => GlobalKey());
    _scheduleFocusedStepVisibility();
  }

  /// 在计划长度或当前步骤变化后同步锚点并重新聚焦。
  /// Synchronizes anchors and refocuses after the plan length or current step changes.
  @override
  void didUpdateWidget(covariant TaskPlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_stepKeys.length != plan.steps.length) {
      _stepKeys = List.generate(plan.steps.length, (_) => GlobalKey());
    }
    if (oldWidget.plan.focusedStepIndex != plan.focusedStepIndex ||
        oldWidget.plan.steps.length != plan.steps.length) {
      _scheduleFocusedStepVisibility();
    }
  }

  /// 等待布局完成后，将当前步骤平滑滚动到步骤列表的中央可见区域。
  /// Waits for layout, then smoothly scrolls the current step into the center of the visible list.
  void _scheduleFocusedStepVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = plan.focusedStepIndex;
      if (index < 0 || index >= _stepKeys.length) return;
      final stepContext = _stepKeys[index].currentContext;
      if (stepContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          stepContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// 构建运行中任务的悬浮分步进度面板与当前步骤指示。
  /// Builds the floating step-progress panel and current-step indicator for a running task.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final focusedIndex = plan.focusedStepIndex;
    final currentStep = focusedIndex < 0 ? 0 : focusedIndex + 1;
    return Semantics(
      container: true,
      label: '执行计划，共 ${plan.steps.length} 步，当前第 $currentStep 步',
      child: Column(
        key: const Key('task-plan-progress'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 17,
                          color: palette.active,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            plan.explanation ?? '执行计划',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: palette.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${plan.completedStepCount}/${plan.steps.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: palette.border),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          plan.steps.length,
                          (index) => KeyedSubtree(
                            key: _stepKeys[index],
                            child: TaskPlanStepRow(
                              key: Key('task-plan-step-$index'),
                              step: plan.steps[index],
                              focused: index == focusedIndex,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('task-plan-current-step'),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TaskPlanStatusMark(
                  status: focusedIndex < 0
                      ? TaskPlanStepStatus.pending
                      : plan.steps[focusedIndex].status,
                  active: true,
                ),
                const SizedBox(width: 7),
                Text(
                  '第 $currentStep / ${plan.steps.length} 步',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
