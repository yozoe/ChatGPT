// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class InspectorThreadRow extends StatelessWidget {
  const InspectorThreadRow({required this.threadId});

  final String? threadId;

  /// 显示当前任务标识，并在空间受限时截断而不撑破信息卡。
  /// Shows the active task identifier without allowing it to overflow the card.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Row(
      children: [
        Icon(Icons.forum_outlined, size: 15, color: palette.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            threadId ?? '尚未创建任务',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ),
      ],
    );
  }
}
