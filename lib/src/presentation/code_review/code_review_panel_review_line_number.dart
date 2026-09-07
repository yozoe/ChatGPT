// Extracted class from code_review_panel.dart.
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

class ReviewLineNumber extends StatelessWidget {
  const ReviewLineNumber({required this.value, super.key});

  final int? value;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      width: 44,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 7),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Text(
        value?.toString() ?? '',
        style: TextStyle(
          color: palette.muted,
          fontFamily: 'monospace',
          fontSize: 10,
        ),
      ),
    );
  }
}
