// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class ThreadStatusMark extends StatelessWidget {
  const ThreadStatusMark({required this.indicator});

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
