// Extracted class from workspace_markdown_preview.dart.
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

class LocationLabel extends StatelessWidget {
  const LocationLabel({required this.line, required this.column, super.key});

  final int line;
  final int? column;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.active.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          column == null ? 'L$line' : 'L$line:C$column',
          style: TextStyle(
            color: palette.active,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
