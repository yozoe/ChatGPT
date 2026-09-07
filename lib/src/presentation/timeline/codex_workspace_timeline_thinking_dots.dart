// Extracted class from codex_workspace_timeline.dart.
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ThinkingDots extends StatelessWidget {
  const ThinkingDots({super.key, required this.progress, required this.color});

  final double? progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final phase = progress == null
            ? 0.0
            : ((progress! * math.pi * 2) - (index * math.pi / 2.4));
        final lift = progress == null ? 0.0 : -math.sin(phase) * 2.4;
        final opacity = progress == null
            ? 0.72
            : 0.48 + ((math.sin(phase) + 1) * 0.24);
        return Padding(
          padding: EdgeInsets.only(right: index == 2 ? 0 : 2.5),
          child: Transform.translate(
            key: ValueKey('live-thinking-dot-$index'),
            offset: Offset(0, lift),
            child: Opacity(
              opacity: opacity,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const SizedBox(width: 3.5, height: 3.5),
              ),
            ),
          ),
        );
      }),
    );
  }
}
