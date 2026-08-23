import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

import 'presentation/codex_workspace.dart';
import 'services/theme_preferences_store.dart';
import 'theme_preferences_controller.dart';

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

class CodexDeskApp extends StatelessWidget {
  const CodexDeskApp({
    super.key,
    this.initialThemePreferences = CodexThemePreferences.defaults,
    this.themePreferencesStore,
  });

  final CodexThemePreferences initialThemePreferences;
  final CodexThemePreferencesStore? themePreferencesStore;

  /// 创建主题与共享控制器共用的 Riverpod 作用域。
  /// Creates the Riverpod scope shared by theme and application controllers.
  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        themePreferencesProvider.overrideWith(
          () => ThemePreferencesNotifier(
            initialPreferences: initialThemePreferences,
            store: themePreferencesStore,
          ),
        ),
      ],
      child: const _CodexDeskAppView(),
    );
  }
}

class _CodexDeskAppView extends ConsumerStatefulWidget {
  const _CodexDeskAppView();

  @override
  ConsumerState<_CodexDeskAppView> createState() => _CodexDeskAppViewState();
}

class _CodexDeskAppViewState extends ConsumerState<_CodexDeskAppView> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 更新亮度模式，并重建根主题。
  /// Updates the brightness mode and rebuilds the root theme.
  void _setThemeMode(ThemeMode value) {
    unawaited(_updateThemePreferences(mode: value));
  }

  /// 更新 UI Kit 配色预设，并重建明暗主题。
  /// Updates the UI Kit color preset and rebuilds light and dark themes.
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
      theme: YeknomWorkbenchTheme.light(preset: preferences.preset),
      darkTheme: YeknomWorkbenchTheme.dark(preset: preferences.preset),
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
