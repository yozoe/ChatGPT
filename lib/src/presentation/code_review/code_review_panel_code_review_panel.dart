// Extracted class from code_review_panel.dart.
import 'package:flutter/material.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_support.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_code_review_panel_state.dart';

class CodeReviewPanel extends StatefulWidget {
  const CodeReviewPanel({
    required this.controller,
    required this.source,
    required this.compact,
    required this.onSourceChanged,
    required this.onCollapse,
    super.key,
  });

  final CodexController controller;
  final CodeReviewSource source;
  final bool compact;
  final ValueChanged<CodeReviewSource> onSourceChanged;
  final VoidCallback onCollapse;

  @override
  State<CodeReviewPanel> createState() => CodeReviewPanelState();
}
