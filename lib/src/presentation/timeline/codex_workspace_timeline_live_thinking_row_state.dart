// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_thinking_row.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_thinking_dots.dart';

class LiveThinkingRowState extends State<LiveThinkingRow>
    with SingleTickerProviderStateMixin {
  static const _animationDuration = Duration(milliseconds: 900);

  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: _animationDuration,
  );
  var _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _animationController.stop();
    } else if (!_animationController.isAnimating) {
      _animationController.repeat();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      key: const Key('live-thinking-row'),
      liveRegion: true,
      label: '正在思考',
      child: Center(
        child: ExcludeSemantics(
          child: DecoratedBox(
            key: const Key('live-thinking-loader'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.module.withValues(alpha: 0.72),
              border: Border.all(color: palette.controlBorder),
            ),
            child: SizedBox.square(
              dimension: 32,
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) => Center(
                  child: ThinkingDots(
                    progress: _reduceMotion ? null : _animationController.value,
                    color: palette.muted,
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
