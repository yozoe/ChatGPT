// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

/// Codex-style compact preview shown beside a hovered user-message rail mark.
class ConversationUserMessageRailPreview extends StatelessWidget {
  const ConversationUserMessageRailPreview({
    required this.messageId,
    required this.text,
    super.key,
  });

  final String messageId;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final normalized = text.trim();
    final lines = normalized.isEmpty ? const ['用户消息'] : normalized.split('\n');
    final title = lines.first.trim().isEmpty ? '用户消息' : lines.first.trim();
    final detail = lines.skip(1).join('\n').trim();
    return IgnorePointer(
      child: Semantics(
        key: ValueKey('conversation-user-message-rail-preview-$messageId'),
        container: true,
        label: '用户消息预览：$normalized',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: detail.isEmpty ? 4 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.trace,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.muted,
                      fontSize: 13,
                      height: 1.65,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
