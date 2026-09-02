import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

import 'package:chatgpt/src/services/theme_preferences_store.dart';

/// 提供应用级主题偏好，并串行保存用户的主题选择。
/// Provides app-wide theme preferences and serializes persistence of user selections.
final themePreferencesProvider =
    NotifierProvider<ThemePreferencesNotifier, CodexThemePreferences>(
      ThemePreferencesNotifier.new,
    );

/// 管理主题偏好状态；应用启动时可由 Provider override 注入已加载的偏好和存储。
/// Manages theme preferences; startup code may override the provider with loaded preferences and a store.
class ThemePreferencesNotifier extends Notifier<CodexThemePreferences> {
  ThemePreferencesNotifier({
    CodexThemePreferences? initialPreferences,
    CodexThemePreferencesStore? store,
  }) : _initialPreferences = initialPreferences,
       _store = store;

  final CodexThemePreferences? _initialPreferences;
  final CodexThemePreferencesStore? _store;
  Future<void> _saveTail = Future<void>.value();

  @override
  CodexThemePreferences build() =>
      _initialPreferences ?? CodexThemePreferences.defaults;

  /// 更新主题模式和配色预设，并将结果排队写入本地偏好。
  /// Updates the theme mode and color preset, queueing the result for local persistence.
  Future<void> update({
    ThemeMode? mode,
    YeknomColorPreset? preset,
    double? sidebarWidth,
  }) {
    final next = state.copyWith(
      mode: mode,
      preset: preset,
      sidebarWidth: sidebarWidth,
    );
    if (next == state) return Future<void>.value();
    state = next;
    final store = _store;
    if (store == null) return Future<void>.value();
    _saveTail = _saveTail.then(
      (_) => store.save(next),
      onError: (_, _) => store.save(next),
    );
    return _saveTail;
  }
}
