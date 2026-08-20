import 'dart:convert';
import 'dart:io';

import '../domain/codex_plugin.dart';

/// 通过本机 Codex CLI 管理 marketplace 插件与启用状态。
/// Manages marketplace plugins and enabled states through the local Codex CLI.
class CodexPluginStore {
  /// 创建插件存储；测试可替换可执行路径和 Codex 用户目录。
  /// Creates a plugin store; tests can replace the executable and Codex home.
  CodexPluginStore({
    String Function()? executableProvider,
    Directory? codexHome,
  }) : _executableProvider = executableProvider ?? _defaultExecutable,
       _codexHome = codexHome;

  final String Function() _executableProvider;
  final Directory? _codexHome;

  /// 返回已安装及当前 marketplace 可安装的插件列表。
  /// Returns installed plugins and plugins available from current marketplaces.
  Future<List<CodexPlugin>> listPlugins() async {
    final output = await _run(const [
      'plugin',
      'list',
      '--available',
      '--json',
    ]);
    final decoded = jsonDecode(output);
    if (decoded is! Map) {
      throw const FormatException('Codex CLI 返回了无效的插件列表。');
    }
    final entries = <Object?>[
      ...(decoded['installed'] as Iterable? ?? const <Object?>[]),
      ...(decoded['available'] as Iterable? ?? const <Object?>[]),
    ];
    final plugins = <String, CodexPlugin>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final plugin = CodexPlugin.fromJson(Map<String, dynamic>.from(entry));
      if (plugin != null) plugins[plugin.id] = plugin;
    }
    return plugins.values.toList(growable: false)..sort((left, right) {
      if (left.installed != right.installed) return left.installed ? -1 : 1;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
  }

  /// 将一个本地插件 marketplace 目录交给 Codex CLI 注册。
  /// Registers a local plugin marketplace directory through the Codex CLI.
  Future<void> addLocalMarketplace(String directory) async {
    final source = directory.trim();
    if (source.isEmpty) throw const FormatException('请选择本地 marketplace 目录。');
    final location = Directory(source);
    if (!await location.exists()) {
      throw StateError('本地 marketplace 目录不存在：$source');
    }
    await _run(['plugin', 'marketplace', 'add', source, '--json']);
  }

  /// 从已注册 marketplace 安装一个插件。
  /// Installs a plugin from a configured marketplace.
  Future<void> installPlugin(CodexPlugin plugin) async {
    if (plugin.installed) return;
    await _run(['plugin', 'add', plugin.id, '--json']);
  }

  /// 更新 `config.toml` 中某个已安装插件的启用状态。
  /// Updates an installed plugin's enabled state in `config.toml`.
  Future<void> setPluginEnabled(CodexPlugin plugin, bool enabled) async {
    if (!plugin.installed) return;
    final config = File(
      '${(_codexHome ?? _defaultCodexHome()).path}/config.toml',
    );
    final current = await config.exists() ? await config.readAsString() : '';
    final next = _replaceEnabledValue(current, plugin.id, enabled);
    await config.writeAsString(next, flush: true);
  }

  /// 执行 CLI 子命令并将失败信息转换为可展示的错误。
  /// Runs a CLI subcommand and converts failures into displayable errors.
  Future<String> _run(List<String> arguments) async {
    final result = await Process.run(
      _executableProvider(),
      arguments,
      runInShell: false,
    ).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) {
      final detail = result.stderr.toString().trim();
      throw StateError(detail.isEmpty ? 'Codex CLI 插件命令执行失败。' : detail);
    }
    return result.stdout.toString();
  }

  /// 在 TOML 中替换或添加指定插件表内的 `enabled` 键。
  /// Replaces or adds the `enabled` key in the target plugin's TOML table.
  String _replaceEnabledValue(String config, String pluginId, bool enabled) {
    final escapedId = pluginId.replaceAll('\\', r'\\').replaceAll('"', r'\"');
    final header = '[plugins."$escapedId"]';
    final headerMatch = RegExp(
      '^${RegExp.escape(header)}'
      r'[ \t]*$',
      multiLine: true,
    ).firstMatch(config);
    final line = 'enabled = $enabled';
    if (headerMatch == null) {
      final separator = config.isEmpty || config.endsWith('\n') ? '' : '\n';
      return '$config$separator\n$header\n$line\n';
    }
    final nextHeaders = RegExp(
      r'^\[',
      multiLine: true,
    ).allMatches(config).where((match) => match.start >= headerMatch.end);
    final tableEnd = nextHeaders.isEmpty
        ? config.length
        : nextHeaders.first.start;
    final table = config.substring(headerMatch.end, tableEnd);
    final enabledMatch = RegExp(
      r'^enabled[ \t]*=[ \t]*(?:true|false)[ \t]*$',
      multiLine: true,
    ).firstMatch(table);
    if (enabledMatch != null) {
      return '${config.substring(0, headerMatch.end + enabledMatch.start)}$line${config.substring(headerMatch.end + enabledMatch.end)}';
    }
    return '${config.substring(0, headerMatch.end)}\n$line${config.substring(headerMatch.end)}';
  }

  /// 返回默认 Codex CLI 可执行文件名称。
  /// Returns the default Codex CLI executable name.
  static String _defaultExecutable() =>
      Platform.environment['CODEX_EXECUTABLE'] ?? 'codex';

  /// 返回默认 Codex 用户配置目录。
  /// Returns the default Codex user configuration directory.
  static Directory _defaultCodexHome() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) throw StateError('无法确定 macOS 用户目录。');
    return Directory('$home/.codex');
  }
}
