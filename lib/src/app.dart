import 'package:flutter/material.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

import 'app_controller.dart';
import 'presentation/codex_workspace.dart';

/// 挂载 Codex Desk 的根 Widget。
/// Mounts the Codex Desk root widget.
void runCodexDesk() {
  runApp(const CodexDeskApp());
}

class CodexDeskApp extends StatefulWidget {
  const CodexDeskApp({super.key});

  /// 创建持有主题选择和共享控制器的应用状态。
  /// Creates application state that owns the theme selection and shared controller.
  @override
  State<CodexDeskApp> createState() => _CodexDeskAppState();
}

class _CodexDeskAppState extends State<CodexDeskApp> {
  late final CodexController _controller;
  ThemeMode _themeMode = ThemeMode.dark;
  YeknomColorPreset _themePreset = YeknomColorPreset.midnight;

  /// 创建一次控制器，确保切换主题不会重置当前工作区与对话状态。
  /// Creates the controller once so theme changes do not reset workspace or conversation state.
  @override
  void initState() {
    super.initState();
    _controller = CodexController();
  }

  /// 更新亮度模式，并重建根主题。
  /// Updates brightness mode and rebuilds the root theme.
  void _setThemeMode(ThemeMode value) {
    setState(() => _themeMode = value);
  }

  /// 更新 UI Kit 配色预设，并重建明暗主题。
  /// Updates the UI Kit color preset and rebuilds light and dark themes.
  void _setThemePreset(YeknomColorPreset value) {
    setState(() => _themePreset = value);
  }

  /// 构建应用主题和初始工作区。
  /// Builds the application themes and initial workspace.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codex Desk',
      debugShowCheckedModeBanner: false,
      theme: YeknomWorkbenchTheme.light(preset: _themePreset),
      darkTheme: YeknomWorkbenchTheme.dark(preset: _themePreset),
      themeMode: _themeMode,
      home: CodexWorkspace(
        controller: _controller,
        themeMode: _themeMode,
        themePreset: _themePreset,
        onThemeModeChanged: _setThemeMode,
        onThemePresetChanged: _setThemePreset,
      ),
    );
  }
}
