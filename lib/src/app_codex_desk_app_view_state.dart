// Extracted class from app.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'codex_hover_popup.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'theme_preferences_controller.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'app_support.dart';
import 'app_codex_desk_app_view.dart';

class CodexDeskAppViewState extends ConsumerState<CodexDeskAppView> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 更新亮度模式，并重建根主题。
  /// Updates the brightness mode and rebuilds the root theme.
  void _setThemeMode(ThemeMode value) {
    unawaited(_updateThemePreferences(mode: value));
  }

  /// 更新项目内配色预设，并重建明暗主题。
  /// Updates the project-owned color preset and rebuilds light and dark themes.
  void _setThemePreset(YeknomColorPreset value) {
    unawaited(_updateThemePreferences(preset: value));
  }

  Future<void> _updateThemePreferences({
    ThemeMode? mode,
    YeknomColorPreset? preset,
  }) async {
    try {
      await ref
          .read(themePreferencesProvider.notifier)
          .update(mode: mode, preset: preset);
    } on Object {
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('主题偏好保存失败；本次切换仍然有效。')));
    }
  }

  /// 构建应用主题和初始工作区。
  /// Builds the application themes and initial workspace.
  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(themePreferencesProvider);
    return MaterialApp(
      title: 'Codex Desk',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: YeknomWorkbenchTheme.light(preset: preferences.preset).copyWith(
        tooltipTheme: const TooltipThemeData(
          waitDuration: codexHoverPopupDelay,
        ),
      ),
      darkTheme: YeknomWorkbenchTheme.dark(preset: preferences.preset).copyWith(
        tooltipTheme: const TooltipThemeData(
          waitDuration: codexHoverPopupDelay,
        ),
      ),
      themeMode: preferences.mode,
      home: CodexWorkspace(
        themeMode: preferences.mode,
        themePreset: preferences.preset,
        onThemeModeChanged: _setThemeMode,
        onThemePresetChanged: _setThemePreset,
      ),
    );
  }
}
