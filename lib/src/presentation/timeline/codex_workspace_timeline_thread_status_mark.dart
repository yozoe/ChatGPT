// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class ThreadStatusMark extends StatelessWidget {
  const ThreadStatusMark({super.key, required this.indicator});

  final ThreadStatusIndicator indicator;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final completed = indicator == ThreadStatusIndicator.completed;
    return Tooltip(
      message: completed ? '任务已完成' : '任务执行出错',
      child: Icon(
        completed ? Icons.circle : Icons.error,
        key: Key(
          completed
              ? 'sidebar-completed-task-indicator'
              : 'sidebar-error-task-indicator',
        ),
        size: completed ? 6 : 16,
        color: completed ? completedThreadIndicatorColor : palette.fault,
      ),
    );
  }
}
