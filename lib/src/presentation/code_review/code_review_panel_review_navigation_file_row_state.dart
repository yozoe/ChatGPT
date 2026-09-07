// Extracted class from code_review_panel.dart.
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_support.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_navigation_file_row.dart';

class ReviewNavigationFileRowState extends State<ReviewNavigationFileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = reviewStats(widget.file.diff);
    final showActions =
        _hovering && (widget.onStage != null || widget.onRevert != null);
    final name = widget.file.path.split('/').last;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        key: ValueKey('code-review-file-${widget.file.path}'),
        color: widget.selected ? palette.selected : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: SizedBox(
            height: 30,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 12 + widget.depth * 14,
                      right: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          reviewFileIcon(widget.file.kind),
                          size: 15,
                          color: widget.selected
                              ? palette.active
                              : palette.muted,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Tooltip(
                            message: widget.file.path,
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 58,
                          child: widget.processing
                              ? Center(
                                  child: SizedBox(
                                    key: const Key(
                                      'code-review-file-operation',
                                    ),
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.4,
                                      color: palette.active,
                                    ),
                                  ),
                                )
                              : showActions
                              ? const SizedBox.shrink()
                              : hasCountableReviewStats(widget.file.diff)
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      '+${stats.additions}',
                                      style: TextStyle(
                                        color: palette.ack,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '-${stats.deletions}',
                                      style: TextStyle(
                                        color: palette.fault,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showActions && !widget.processing)
                  Positioned(
                    right: 7,
                    top: 1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onStage != null)
                          IconButton(
                            tooltip: '暂存文件',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 26,
                              height: 28,
                            ),
                            onPressed: widget.writesEnabled
                                ? widget.onStage
                                : null,
                            icon: const Icon(Icons.add_box_outlined, size: 15),
                          ),
                        if (widget.onRevert != null)
                          IconButton(
                            tooltip: '还原文件改动',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 26,
                              height: 28,
                            ),
                            onPressed: widget.writesEnabled
                                ? widget.onRevert
                                : null,
                            icon: const Icon(Icons.restore_outlined, size: 15),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
