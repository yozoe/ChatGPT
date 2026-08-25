import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'package:chatgpt/src/theme_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

final class _MemoryThemeStore implements CodexThemePreferencesStore {
  final List<CodexThemePreferences> saved = [];

  @override
  Future<CodexThemePreferences> load() async => CodexThemePreferences.defaults;

  @override
  Future<void> save(CodexThemePreferences preferences) async {
    saved.add(preferences);
  }
}

final class _FailingThenMemoryThemeStore implements CodexThemePreferencesStore {
  final List<CodexThemePreferences> saved = [];
  var saveAttempts = 0;

  @override
  Future<CodexThemePreferences> load() async => CodexThemePreferences.defaults;

  @override
  Future<void> save(CodexThemePreferences preferences) async {
    saveAttempts++;
    if (saveAttempts == 1) throw StateError('first save failed');
    saved.add(preferences);
  }
}

void main() {
  test('theme provider owns and persists app-wide preferences', () async {
    final store = _MemoryThemeStore();
    final container = ProviderContainer(
      overrides: [
        themePreferencesProvider.overrideWith(
          () => ThemePreferencesNotifier(
            initialPreferences: CodexThemePreferences.defaults,
            store: store,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(themePreferencesProvider.notifier)
        .update(mode: ThemeMode.light, preset: YeknomColorPreset.cobalt);

    expect(
      container.read(themePreferencesProvider),
      const CodexThemePreferences(
        mode: ThemeMode.light,
        preset: YeknomColorPreset.cobalt,
      ),
    );
    expect(store.saved, [container.read(themePreferencesProvider)]);
  });

  test('theme persistence continues after an earlier save fails', () async {
    final store = _FailingThenMemoryThemeStore();
    final container = ProviderContainer(
      overrides: [
        themePreferencesProvider.overrideWith(
          () => ThemePreferencesNotifier(
            initialPreferences: CodexThemePreferences.defaults,
            store: store,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(themePreferencesProvider.notifier);

    await expectLater(
      notifier.update(mode: ThemeMode.light),
      throwsA(isA<StateError>()),
    );
    await notifier.update(preset: YeknomColorPreset.cobalt);

    expect(store.saveAttempts, 2);
    expect(store.saved, [container.read(themePreferencesProvider)]);
  });
}
