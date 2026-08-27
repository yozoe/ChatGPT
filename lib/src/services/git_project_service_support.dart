// Shared declarations extracted from git_project_service.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/domain/git_project_status.dart';

/// 读取项目 Git 状态和 Diff，并仅在用户明确操作时执行受限的 Git 写入命令。
/// Reads project Git state and diffs, running restricted Git writes only after an explicit user action.
