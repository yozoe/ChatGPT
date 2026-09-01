// Extracted state from codex_workspace_conversation_user_message_rail.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail_mark.dart';

class ConversationUserMessageRailState
    extends State<ConversationUserMessageRail> {
  int? hoveredIndex;

  void updateHoveredIndex(int? index) {
    if (hoveredIndex == index) return;
    setState(() => hoveredIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('conversation-user-message-rail'),
      container: true,
      label: '用户消息导航',
      child: MouseRegion(
        onExit: (_) => updateHoveredIndex(null),
        child: SizedBox(
          width: 28,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < widget.messages.length; index++)
                      MouseRegion(
                        key: ValueKey(
                          'conversation-user-message-rail-hit-${widget.messages[index].id}',
                        ),
                        opaque: true,
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => updateHoveredIndex(index),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await widget.onMessageSelected(
                              widget.messages[index].id,
                            );
                          },
                          child: Semantics(
                            button: true,
                            child: SizedBox(
                              width: 28,
                              height: 9,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ConversationUserMessageRailMark(
                                  messageId: widget.messages[index].id,
                                  text: widget.messages[index].detail,
                                  distanceFromHover: hoveredIndex == null
                                      ? null
                                      : (hoveredIndex! - index).abs(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
