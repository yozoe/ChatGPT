import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

import 'presentation/codex_workspace.dart';
import 'services/theme_preferences_store.dart';

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

class CodexDeskApp extends StatefulWidget {
  const CodexDeskApp({
    super.key,
    this.initialThemePreferences = CodexThemePreferences.defaults,
    this.themePreferencesStore,
  });

  final CodexThemePreferences initialThemePreferences;
  final CodexThemePreferencesStore? themePreferencesStore;

  /// 创建持有主题选择和共享控制器的应用状态。
  /// Creates application state that owns the theme selection and shared controller.
  @override
  State<CodexDeskApp> createState() => _CodexDeskAppState();
}

class _CodexDeskAppState extends State<CodexDeskApp> {
  late CodexThemePreferences _themePreferences;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  Future<void> _themeSaveTail = Future<void>.value();

  /// 初始化主题偏好；共享控制器由应用根部的 Riverpod Provider 持有。
  /// Initializes theme preferences; Riverpod at the app root owns the shared controller.
  @override
  void initState() {
    super.initState();
    _themePreferences = widget.initialThemePreferences;
  }

  /// 更新亮度模式，并重建根主题。
  /// Updates brightness mode and rebuilds the root theme.
  void _setThemeMode(ThemeMode value) {
    _updateThemePreferences(_themePreferences.copyWith(mode: value));
  }

  /// 更新 UI Kit 配色预设，并重建明暗主题。
  /// Updates the UI Kit color preset and rebuilds light and dark themes.
  void _setThemePreset(YeknomColorPreset value) {
    _updateThemePreferences(_themePreferences.copyWith(preset: value));
  }

  void _updateThemePreferences(CodexThemePreferences next) {
    if (next == _themePreferences) return;
    setState(() => _themePreferences = next);
    final store = widget.themePreferencesStore;
    if (store == null) return;
    _themeSaveTail = _themeSaveTail.then((_) async {
      try {
        await store.save(next);
      } on Object {
        _messengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('主题偏好保存失败；本次切换仍然有效。')));
      }
    });
  }

  /// 构建应用主题和初始工作区。
  /// Builds the application themes and initial workspace.
  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Codex Desk',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        theme: YeknomWorkbenchTheme.light(preset: _themePreferences.preset),
        darkTheme: YeknomWorkbenchTheme.dark(preset: _themePreferences.preset),
        themeMode: _themePreferences.mode,
        home: CodexWorkspace(
          themeMode: _themePreferences.mode,
          themePreset: _themePreferences.preset,
          onThemeModeChanged: _setThemeMode,
          onThemePresetChanged: _setThemePreset,
        ),
      ),
    );
  }
}
