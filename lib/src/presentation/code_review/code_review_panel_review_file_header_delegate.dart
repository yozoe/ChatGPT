// Extracted class from code_review_panel.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_support.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_file.dart';

class ReviewFileHeaderDelegate extends SliverPersistentHeaderDelegate {
  const ReviewFileHeaderDelegate({required this.key, required this.file});

  final GlobalKey key;
  final ReviewFile file;

  @override
  double get minExtent => 36;

  @override
  double get maxExtent => 36;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final palette = YeknomPalette.of(context);
    final stats = reviewStats(file.diff);
    return Container(
      key: key,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: overlapsContent ? palette.raised : palette.module,
        border: Border(
          top: BorderSide(color: palette.border),
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 0) return const SizedBox.shrink();
          final showLeading = constraints.maxWidth >= 48;
          final showStats = constraints.maxWidth >= 112;
          final showTruncation = file.truncated && constraints.maxWidth >= 148;
          final trailingMaximum = math.min(
            80.0,
            constraints.maxWidth -
                (showLeading ? 24 : 0) -
                (showTruncation ? 23 : 0) -
                24,
          );
          return Row(
            children: [
              if (showLeading) ...[
                Icon(reviewFileIcon(file.kind), size: 16, color: palette.muted),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Tooltip(
                  message: file.path,
                  child: Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (showTruncation)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: palette.warning,
                  ),
                ),
              if (showStats)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: trailingMaximum),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          file.diff.trim().isEmpty
                              ? '+?'
                              : '+${stats.additions}',
                          style: TextStyle(color: palette.ack, fontSize: 11),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          file.diff.trim().isEmpty
                              ? '-?'
                              : '-${stats.deletions}',
                          style: TextStyle(color: palette.fault, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant ReviewFileHeaderDelegate oldDelegate) =>
      oldDelegate.file != file || oldDelegate.key != key;
}
