// Extracted class from code_review_panel.dart.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_navigation_file_row_state.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_file.dart';

class ReviewNavigationFileRow extends StatefulWidget {
  const ReviewNavigationFileRow({
    required this.file,
    required this.depth,
    required this.selected,
    required this.writesEnabled,
    required this.processing,
    required this.onTap,
    required this.onStage,
    required this.onRevert,
    super.key,
  });

  final ReviewFile file;
  final int depth;
  final bool selected;
  final bool writesEnabled;
  final bool processing;
  final VoidCallback onTap;
  final Future<void> Function()? onStage;
  final Future<void> Function()? onRevert;

  @override
  State<ReviewNavigationFileRow> createState() =>
      ReviewNavigationFileRowState();
}
