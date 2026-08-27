// Extracted class from theme_preferences_store.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'theme_preferences_store_support.dart';

final class CodexThemePreferences {
  const CodexThemePreferences({required this.mode, required this.preset});

  static const defaults = CodexThemePreferences(
    mode: ThemeMode.dark,
    preset: YeknomColorPreset.midnight,
  );

  final ThemeMode mode;
  final YeknomColorPreset preset;

  CodexThemePreferences copyWith({
    ThemeMode? mode,
    YeknomColorPreset? preset,
  }) => CodexThemePreferences(
    mode: mode ?? this.mode,
    preset: preset ?? this.preset,
  );

  Map<String, Object> toJson() => <String, Object>{
    'themeMode': mode.name,
    'colorPreset': preset.name,
  };

  factory CodexThemePreferences.fromJson(Object? value) {
    if (value is! Map) return defaults;
    return CodexThemePreferences(
      mode: ThemeMode.values.firstWhere(
        (candidate) => candidate.name == value['themeMode'],
        orElse: () => defaults.mode,
      ),
      preset: YeknomColorPreset.values.firstWhere(
        (candidate) => candidate.name == value['colorPreset'],
        orElse: () => defaults.preset,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CodexThemePreferences &&
      other.mode == mode &&
      other.preset == preset;

  @override
  int get hashCode => Object.hash(mode, preset);
}
