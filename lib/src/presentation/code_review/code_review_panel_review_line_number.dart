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
