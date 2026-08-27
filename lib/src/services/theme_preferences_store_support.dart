// Shared declarations extracted from theme_preferences_store.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'theme_preferences_store_codex_theme_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

/// 用户选择的主题模式与项目配色预设，可安全序列化到应用目录。
/// User-selected theme mode and project-owned color preset, safely serializable in the app directory.
@immutable
/// 主题偏好的存取边界，便于测试替换文件系统实现。
/// Storage boundary for theme preferences, allowing file-system replacement in tests.
abstract interface class CodexThemePreferencesStore {
  Future<CodexThemePreferences> load();

  Future<void> save(CodexThemePreferences preferences);
}

/// 以临时文件加重命名写入主题偏好，避免中断写入留下半份 JSON。
/// Writes theme preferences through temp-file rename so interrupted writes do not leave partial JSON.
