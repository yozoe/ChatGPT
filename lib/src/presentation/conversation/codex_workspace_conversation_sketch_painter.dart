import 'package:flutter/material.dart';

class SketchPainter extends CustomPainter {
  const SketchPainter(this.points, {required this.strokeColor});

  final List<Offset?> points;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      if (start != null && end != null) {
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.strokeColor != strokeColor;
}
