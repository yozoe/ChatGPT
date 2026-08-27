// Extracted class from git_project_service.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'git_project_service_support.dart';

class GitDiffCommandResult {
  const GitDiffCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.truncated,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool truncated;
}
