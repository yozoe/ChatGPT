// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class CodexLoadingMarkPainter extends CustomPainter {
  const CodexLoadingMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.29;
    final stroke = Paint()
      ..color = const Color(0xFFF48A27)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.105
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var index = 0; index < 6; index++) {
      final angle = index * 3.141592653589793 / 3;
      final start = Offset(
        center.dx + radius * 0.55 * _cos(angle),
        center.dy + radius * 0.55 * _sin(angle),
      );
      final path = Path()..moveTo(start.dx, start.dy);
      path.cubicTo(
        center.dx + radius * 1.26 * _cos(angle - 0.65),
        center.dy + radius * 1.26 * _sin(angle - 0.65),
        center.dx + radius * 1.26 * _cos(angle + 0.65),
        center.dy + radius * 1.26 * _sin(angle + 0.65),
        start.dx,
        start.dy,
      );
      canvas.drawPath(path, stroke);
    }
  }

  double _cos(double value) => math.cos(value);
  double _sin(double value) => math.sin(value);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
