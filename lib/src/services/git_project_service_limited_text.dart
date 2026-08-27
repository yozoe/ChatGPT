// Extracted class from git_project_service.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'git_project_service_support.dart';

class LimitedText {
  const LimitedText({required this.content, required this.truncated});

  final String content;
  final bool truncated;
}
