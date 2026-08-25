import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'codex_hover_popup.dart';
import 'presentation/codex_workspace.dart';
import 'services/theme_preferences_store.dart';
import 'theme_preferences_controller.dart';
import 'theme/yeknom_workbench.dart';

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

/// 消费主题状态并拥有全局错误提示入口的内部应用视图。
/// Internal app view that consumes theme state and owns global error feedback.
class _CodexDeskAppView extends ConsumerStatefulWidget {
  const _CodexDeskAppView();

  @override
  ConsumerState<_CodexDeskAppView> createState() => _CodexDeskAppViewState();
}

/// 将持久化失败降级为非阻塞提示，保留本次内存中的主题选择。
/// Keeps a chosen theme in memory when persistence fails and reports it non-blockingly.
class _CodexDeskAppViewState extends ConsumerState<_CodexDeskAppView> {
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
