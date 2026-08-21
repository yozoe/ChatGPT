import 'dart:io';

import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

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
}
