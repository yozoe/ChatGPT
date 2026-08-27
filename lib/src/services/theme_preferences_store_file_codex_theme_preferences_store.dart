// Extracted class from theme_preferences_store.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'theme_preferences_store_support.dart';
import 'theme_preferences_store_codex_theme_preferences.dart';

final class FileCodexThemePreferencesStore
    implements CodexThemePreferencesStore {
  FileCodexThemePreferencesStore({File? file, Random? random})
    : _fixedFile = file,
      _random = random ?? Random.secure();

  final File? _fixedFile;
  final Random _random;

  @override
  Future<CodexThemePreferences> load() async {
    try {
      final file = _file();
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return CodexThemePreferences.defaults;
      }
      if (await file.length() > 64 * 1024) {
        return CodexThemePreferences.defaults;
      }
      return CodexThemePreferences.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } on Object {
      return CodexThemePreferences.defaults;
    }
  }

  @override
  Future<void> save(CodexThemePreferences preferences) async {
    final file = _file();
    await file.parent.create(recursive: true);
    File? temporaryFile;
    try {
      temporaryFile = File('${file.path}.tmp.$pid.${_randomToken()}');
      await temporaryFile.create(exclusive: true);
      await temporaryFile.writeAsString(
        '${jsonEncode(preferences.toJson())}\n',
        flush: true,
      );
      await temporaryFile.rename(file.path);
      temporaryFile = null;
    } finally {
      if (temporaryFile != null) {
        try {
          if (await temporaryFile.exists()) await temporaryFile.delete();
        } on Object {
          // Preserve the write failure when temporary cleanup also fails.
        }
      }
    }
  }

  File _file() {
    final fixedFile = _fixedFile;
    if (fixedFile != null) return fixedFile;
    final home = Platform.environment['HOME']?.trim();
    final String directory;
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      directory = '$home/Library/Application Support/Codex Desk';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA']?.trim();
      if (appData == null || appData.isEmpty) {
        throw StateError('APPDATA is unavailable.');
      }
      directory = '$appData${Platform.pathSeparator}Codex Desk';
    } else if (home != null && home.isNotEmpty) {
      final configHome = Platform.environment['XDG_CONFIG_HOME']?.trim();
      directory = configHome != null && configHome.isNotEmpty
          ? '$configHome${Platform.pathSeparator}codex-desk'
          : '$home${Platform.pathSeparator}.config${Platform.pathSeparator}codex-desk';
    } else {
      throw StateError('A persistent application directory is unavailable.');
    }
    return File('$directory${Platform.pathSeparator}ui-preferences.json');
  }

  String _randomToken() => List<int>.generate(
    12,
    (_) => _random.nextInt(256),
    growable: false,
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}
