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

class ReviewFile {
  const ReviewFile({
    required this.path,
    required this.kind,
    required this.diff,
    this.truncated = false,
    this.error,
    this.gitChange,
  });

  final String path;
  final String kind;
  final String diff;
  final bool truncated;
  final String? error;
  final GitProjectChange? gitChange;

  @override
  bool operator ==(Object other) =>
      other is ReviewFile &&
      path == other.path &&
      kind == other.kind &&
      diff == other.diff &&
      truncated == other.truncated &&
      error == other.error;

  @override
  int get hashCode => Object.hash(path, kind, diff, truncated, error);
}
