import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/yeknom_workbench.dart';

/// 用户选择的主题模式与项目配色预设，可安全序列化到应用目录。
/// User-selected theme mode and project-owned color preset, safely serializable in the app directory.
@immutable
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

/// 主题偏好的存取边界，便于测试替换文件系统实现。
/// Storage boundary for theme preferences, allowing file-system replacement in tests.
abstract interface class CodexThemePreferencesStore {
  Future<CodexThemePreferences> load();

  Future<void> save(CodexThemePreferences preferences);
}

/// 以临时文件加重命名写入主题偏好，避免中断写入留下半份 JSON。
/// Writes theme preferences through temp-file rename so interrupted writes do not leave partial JSON.
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
