// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_user_message_bubble.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_timeline_image.dart';

class UserMessageBubbleState extends State<UserMessageBubble> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topRight,
        children: [
          MouseRegion(
            key: const Key('timeline-user-message-hover-region'),
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Container(
                key: const Key('timeline-user-message'),
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectionArea(child: Text(widget.entry.detail)),
                    if (widget.entry.imagePaths.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final path in widget.entry.imagePaths)
                              TimelineImage(path: path),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_hovering)
            Positioned(
              right: 0,
              bottom: -18.5,
              child: Text(
                messageTimeLabel(widget.entry.createdAt),
                key: const Key('timeline-user-message-time'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.muted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
