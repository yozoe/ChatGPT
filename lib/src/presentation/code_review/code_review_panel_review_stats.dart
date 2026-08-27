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

class ReviewStats {
  const ReviewStats({this.additions = 0, this.deletions = 0});

  final int additions;
  final int deletions;

  ReviewStats operator +(ReviewStats other) => ReviewStats(
    additions: additions + other.additions,
    deletions: deletions + other.deletions,
  );
}
