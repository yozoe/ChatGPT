// Extracted class from workspace_markdown_preview.dart.
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_support.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_mode_button.dart';

class MarkdownModeSwitch extends StatelessWidget {
  const MarkdownModeSwitch({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final MarkdownViewMode mode;
  final ValueChanged<MarkdownViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModeButton(
              key: const Key('markdown-preview-mode-button'),
              label: '预览',
              selected: mode == MarkdownViewMode.preview,
              onPressed: () => onChanged(MarkdownViewMode.preview),
            ),
            ModeButton(
              key: const Key('markdown-source-mode-button'),
              label: '源码',
              selected: mode == MarkdownViewMode.source,
              onPressed: () => onChanged(MarkdownViewMode.source),
            ),
          ],
        ),
      ),
    );
  }
}
