import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_new_task_suggestion_card.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

/// Local hover/focus state for a new-task prompt starter.
class NewTaskSuggestionCardState extends State<NewTaskSuggestionCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final radius = BorderRadius.circular(16);
    return SizedBox(
      width: widget.width,
      height: 106,
      child: Semantics(
        button: true,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: hovered
                  ? palette.raised.withValues(alpha: palette.dark ? 0.72 : 1)
                  : palette.bench.withValues(alpha: 0.18),
              borderRadius: radius,
              border: Border.all(
                color: hovered ? palette.controlBorder : palette.border,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('new-task-suggestion-${widget.label}'),
                borderRadius: radius,
                onTap: widget.onPressed,
                focusColor: palette.active.withValues(alpha: 0.08),
                hoverColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 14, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(widget.icon, size: 17, color: widget.iconColor),
                      const Spacer(),
                      Text(
                        widget.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.trace,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
