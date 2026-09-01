// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

/// One compact line in the fixed user-message rail.
class ConversationUserMessageRailMark extends StatelessWidget {
  const ConversationUserMessageRailMark({
    required this.messageId,
    required this.text,
    required this.distanceFromHover,
    super.key,
  });

  final String messageId;
  final String text;
  final int? distanceFromHover;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final width = switch (distanceFromHover) {
      0 => 28.0,
      1 => 22.0,
      2 => 17.0,
      3 => 12.0,
      _ => 8.0,
    };
    final color = switch (distanceFromHover) {
      0 => palette.trace.withValues(alpha: 0.94),
      1 => palette.muted.withValues(alpha: 0.82),
      2 => palette.muted.withValues(alpha: 0.68),
      3 => palette.muted.withValues(alpha: 0.56),
      _ => palette.muted.withValues(alpha: 0.52),
    };
    final normalizedText = text.trim();
    return Semantics(
      key: ValueKey('conversation-user-message-rail-mark-$messageId'),
      container: true,
      label: normalizedText.isEmpty ? '用户消息' : '用户消息：$normalizedText',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        width: width,
        height: 1,
        color: color,
      ),
    );
  }
}
