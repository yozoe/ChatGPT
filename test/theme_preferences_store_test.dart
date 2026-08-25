import 'dart:io';

import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme preferences round-trip every supported selection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'codex-desk-theme-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileCodexThemePreferencesStore(
      file: File('${directory.path}/ui-preferences.json'),
    );

    for (final mode in ThemeMode.values) {
      for (final preset in YeknomColorPreset.values) {
        final expected = CodexThemePreferences(mode: mode, preset: preset);
        await store.save(expected);
        expect(await store.load(), expected);
      }
    }
  });

  test('theme preferences safely default when the file is damaged', () async {
    final directory = await Directory.systemTemp.createTemp(
      'codex-desk-theme-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/ui-preferences.json');
    final store = FileCodexThemePreferencesStore(file: file);

    await file.writeAsString('{invalid');

    expect(await store.load(), CodexThemePreferences.defaults);
  });

  test('every preset has a distinct accessible accent in both modes', () {
    for (final brightness in Brightness.values) {
      final palettes = YeknomColorPreset.values
          .map((preset) => YeknomPalette.fromPreset(preset, brightness))
          .toList(growable: false);
      expect(
        palettes.map((palette) => palette.active).toSet(),
        hasLength(YeknomColorPreset.values.length),
      );
      for (final preset in YeknomColorPreset.values) {
        final theme = brightness == Brightness.dark
            ? YeknomWorkbenchTheme.dark(preset: preset)
            : YeknomWorkbenchTheme.light(preset: preset);
        expect(
          _contrastRatio(
            theme.colorScheme.primary,
            theme.colorScheme.onPrimary,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$preset $brightness primary foreground must remain legible',
        );
      }
    }
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
