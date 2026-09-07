// Extracted class from workspace_markdown_preview.dart.
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

class ImageFallback extends StatelessWidget {
  const ImageFallback({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 18,
            color: palette.muted,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, style: TextStyle(color: palette.muted)),
          ),
        ],
      ),
    );
  }
}
