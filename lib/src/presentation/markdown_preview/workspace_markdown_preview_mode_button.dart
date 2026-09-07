// Extracted class from workspace_markdown_preview.dart.
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

class ModeButton extends StatelessWidget {
  const ModeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(54, 28),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: selected ? palette.trace : palette.muted,
        backgroundColor: selected ? palette.selected : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
