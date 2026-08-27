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
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_directory.dart';

class ReviewTreeRow {
  const ReviewTreeRow.directory(this.directory, this.depth) : file = null;
  const ReviewTreeRow.file(this.file, this.depth) : directory = null;

  final ReviewDirectory? directory;
  final ReviewFile? file;
  final int depth;
}
