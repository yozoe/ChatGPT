// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';

class ScheduledTaskRow extends StatelessWidget {
  const ScheduledTaskRow({
    required this.task,
    required this.timeLabel,
    required this.onCancel,
  });

  final ScheduledTask task;
  final String timeLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Icon(Icons.schedule_outlined, color: palette.active),
      title: Text(task.prompt, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(timeLabel, style: TextStyle(color: palette.muted)),
      trailing: IconButton(
        tooltip: '取消安排',
        onPressed: onCancel,
        icon: const Icon(Icons.close, size: 19),
      ),
    );
  }
}
