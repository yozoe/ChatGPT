import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_elapsed_turn_group.dart';

class ElapsedTurnGroupState extends State<ElapsedTurnGroup> {
  static const _animationDuration = Duration(milliseconds: 180);
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final label = '连续 ${widget.entries.length} 个回合';
    return Semantics(
      container: true,
      button: true,
      expanded: _expanded,
      label: '$label，点击${_expanded ? '收起' : '展开'}每回合耗时',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('elapsed-turn-group-toggle'),
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 4, 5, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 15, color: palette.muted),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: _animationDuration,
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_right,
                        size: 16,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: _animationDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 0, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in widget.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              entry.title,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.faint),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Divider(height: 1),
          ),
        ],
      ),
    );
  }
}
