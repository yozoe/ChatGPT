// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class TaskPlanStatusMark extends StatelessWidget {
  const TaskPlanStatusMark({
    super.key,
    required this.status,
    required this.active,
  });

  final TaskPlanStepStatus status;
  final bool active;

  /// 构建静态状态标记，避免持续动画干扰阅读和 Widget 测试稳定性。
  /// Builds a static status mark to avoid perpetual motion and unstable widget tests.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (status == TaskPlanStepStatus.completed) {
      return Icon(Icons.check_circle, size: 16, color: palette.ack);
    }
    final color = active ? palette.active : palette.muted;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: active ? 2 : 1.5),
      ),
      alignment: Alignment.center,
      child: status == TaskPlanStepStatus.inProgress
          ? Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
          : null,
    );
  }
}
