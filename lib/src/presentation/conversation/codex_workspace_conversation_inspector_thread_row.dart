// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class InspectorThreadRow extends StatelessWidget {
  const InspectorThreadRow({super.key, required this.threadId});

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
