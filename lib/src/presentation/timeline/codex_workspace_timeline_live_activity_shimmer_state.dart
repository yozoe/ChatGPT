// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_activity_shimmer.dart';

class LiveActivityShimmerState extends State<LiveActivityShimmer>
    with SingleTickerProviderStateMixin {
  static const _animationDuration = Duration(milliseconds: 760);

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
    final highlightColor = Color.lerp(
      palette.trace,
      Theme.of(context).colorScheme.onSurface,
      0.38,
    )!;
    return AnimatedBuilder(
      animation: _animationController,
      child: widget.child,
      builder: (context, child) {
        final progress = _reduceMotion ? 0.5 : _animationController.value;
        final highlightStart = -1.35 + (progress * 2.7);
        return ShaderMask(
          key: widget.shimmerKey,
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(highlightStart, 0),
            end: Alignment(highlightStart + 0.8, 0),
            colors: [
              palette.muted.withValues(alpha: 0.78),
              highlightColor,
              palette.muted.withValues(alpha: 0.78),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
