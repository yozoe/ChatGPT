// Shared declarations extracted from app.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'codex_hover_popup.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'theme_preferences_controller.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'app_codex_desk_app.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'codex_hover_popup.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'theme_preferences_controller.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

/// 挂载 Codex Desk 的根 Widget。
/// Mounts the Codex Desk root widget.
Future<void> runCodexDesk() async {
  final store = FileCodexThemePreferencesStore();
  final preferences = await store.load();
  runApp(
    CodexDeskApp(
      initialThemePreferences: preferences,
      themePreferencesStore: store,
    ),
  );
}

/// 应用根部：建立可替换的 Provider 容器，并把启动时恢复的主题偏好注入其中。
/// Root application widget that injects restored theme preferences into a replaceable Provider scope.

/// 消费主题状态并拥有全局错误提示入口的内部应用视图。
/// Internal app view that consumes theme state and owns global error feedback.

/// 将持久化失败降级为非阻塞提示，保留本次内存中的主题选择。
/// Keeps a chosen theme in memory when persistence fails and reports it non-blockingly.
