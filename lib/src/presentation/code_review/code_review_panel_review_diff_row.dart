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
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_line_number.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_row.dart';

class ReviewDiffRow extends StatelessWidget {
  const ReviewDiffRow({
    required this.row,
    required this.horizontalController,
    required this.contentWidth,
    super.key,
  });

  final ReviewRow row;
  final ScrollController horizontalController;
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final background = switch (row.kind) {
      ReviewRowKind.addition => palette.ack.withValues(alpha: 0.10),
      ReviewRowKind.deletion => palette.fault.withValues(alpha: 0.10),
      ReviewRowKind.hunk => palette.active.withValues(alpha: 0.07),
      ReviewRowKind.collapsed => palette.raised,
      _ => Colors.transparent,
    };
    final color = switch (row.kind) {
      ReviewRowKind.addition => palette.ack,
      ReviewRowKind.deletion => palette.fault,
      ReviewRowKind.hunk => palette.active,
      ReviewRowKind.metadata || ReviewRowKind.noNewline => palette.muted,
      ReviewRowKind.error => palette.fault,
      _ => palette.trace,
    };
    return Container(
      height: row.kind == ReviewRowKind.collapsed ? 28 : 20,
      color: background,
      child: Row(
        children: [
          ReviewLineNumber(value: row.oldLine),
          ReviewLineNumber(value: row.newLine),
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: horizontalController,
                builder: (context, child) {
                  final offset = horizontalController.hasClients
                      ? horizontalController.offset
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(-offset, 0),
                    child: child,
                  );
                },
                child: SizedBox(
                  width: contentWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        row.text,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: color,
                          fontFamily: 'monospace',
                          fontSize: row.kind == ReviewRowKind.collapsed
                              ? 11
                              : 12,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
