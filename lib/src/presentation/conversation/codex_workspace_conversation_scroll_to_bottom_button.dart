import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// A compact control that returns a reading timeline to its latest entry.
class ConversationScrollToBottomButton extends StatelessWidget {
  const ConversationScrollToBottomButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      button: true,
      label: '滚动到最新消息',
      child: Tooltip(
        message: '滚动到最新消息',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('conversation-scroll-to-bottom-button'),
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.raised,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.arrow_downward_rounded,
                size: 20,
                color: palette.trace,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
