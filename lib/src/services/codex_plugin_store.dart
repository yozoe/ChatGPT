import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/codex_plugin.dart';
import '../domain/codex_marketplace.dart';

/// 可替换的 CLI 执行边界，使插件命令可在测试中脱离真实子进程验证。
/// Replaceable CLI runner boundary for testing plugin commands without real subprocesses.
typedef CodexPluginProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// 延迟解析实际 Codex CLI 路径，支持 App Server 已发现的可执行文件。
/// Lazily resolves the actual Codex CLI path, including one discovered by App Server.
typedef CodexPluginExecutableProvider = FutureOr<String> Function();

/// 通过本机 Codex CLI 管理 marketplace 插件与启用状态。
/// Manages marketplace plugins and enabled states through the local Codex CLI.
class CodexPluginStore {
  static const _commandTimeout = Duration(seconds: 20);

  /// 创建插件存储；测试可替换可执行路径和 Codex 用户目录。
  /// Creates a plugin store; tests can replace the executable and Codex home.
  CodexPluginStore({
    CodexPluginExecutableProvider? executableProvider,
    Directory? codexHome,
    CodexPluginProcessRunner? processRunner,
  }) : _executableProvider = executableProvider ?? _defaultExecutable,
       _codexHome = codexHome,
       _processRunner = processRunner ?? _defaultProcessRunner;

  final CodexPluginExecutableProvider _executableProvider;
  final Directory? _codexHome;
  final CodexPluginProcessRunner _processRunner;
  Future<void> _configWriteQueue = Future.value();

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
    if ((decoded['installed'] != null && decoded['installed'] is! Iterable) ||
        (decoded['available'] != null && decoded['available'] is! Iterable)) {
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

  /// 注册一个本地插件 marketplace 目录，供兼容现有调用方使用。
  /// Registers a local plugin marketplace directory for existing callers.
  Future<void> addLocalMarketplace(String directory) async {
    final source = directory.trim();
    if (source.isEmpty) throw const FormatException('请选择本地 marketplace 目录。');
    final location = Directory(source);
    if (!await location.exists()) {
      throw StateError('本地 marketplace 目录不存在：$source');
    }
    await addMarketplace(source);
  }

  /// 注册本地目录、Git URL 或 `owner/repo` 形式的 marketplace 来源。
  /// Registers a local directory, Git URL, or `owner/repo` marketplace source.
  Future<void> addMarketplace(String source) async {
    final value = source.trim();
    if (value.isEmpty) throw const FormatException('请输入 marketplace 来源。');
    await _run(['plugin', 'marketplace', 'add', value, '--json']);
  }

  /// 返回当前 Codex CLI 正在使用的 marketplace 列表。
  /// Returns the marketplaces currently considered by the Codex CLI.
  Future<List<CodexMarketplace>> listMarketplaces() async {
    final output = await _run(const [
      'plugin',
      'marketplace',
      'list',
      '--json',
    ]);
    final decoded = jsonDecode(output);
    if (decoded is! Map || decoded['marketplaces'] is! Iterable) {
      throw const FormatException('Codex CLI 返回了无效的 marketplace 列表。');
    }
    return (decoded['marketplaces'] as Iterable)
        .whereType<Map>()
        .map(
          (value) =>
              CodexMarketplace.fromJson(Map<String, dynamic>.from(value)),
        )
        .whereType<CodexMarketplace>()
        .toList(growable: false);
  }

  /// 刷新一个 Git marketplace；名称为空时刷新所有 Git marketplace。
  /// Refreshes one Git marketplace, or every Git marketplace when name is null.
  Future<void> upgradeMarketplace(String? name) async {
    final arguments = ['plugin', 'marketplace', 'upgrade'];
    if (name?.trim().isNotEmpty == true) arguments.add(name!.trim());
    arguments.add('--json');
    await _run(arguments);
  }

  /// 移除指定 marketplace 配置；Codex CLI 会决定是否允许该操作。
  /// Removes a marketplace configuration; the Codex CLI decides whether it is allowed.
  Future<void> removeMarketplace(CodexMarketplace marketplace) async {
    await _run(['plugin', 'marketplace', 'remove', marketplace.name, '--json']);
  }

  /// 从已注册 marketplace 安装一个插件。
  /// Installs a plugin from a configured marketplace.
  Future<void> installPlugin(CodexPlugin plugin) async {
    if (plugin.installed) return;
    await _run(['plugin', 'add', plugin.id, '--json']);
  }

  /// 卸载指定插件；Codex CLI 会保留受管理或受保护插件的限制。
  /// Uninstalls a plugin while retaining Codex CLI restrictions for managed plugins.
  Future<void> removePlugin(CodexPlugin plugin) async {
    if (!plugin.installed) return;
    await _run(['plugin', 'remove', plugin.id, '--json']);
  }

  /// 更新 `config.toml` 中某个已安装插件的启用状态。
  /// Updates an installed plugin's enabled state in `config.toml`.
  Future<void> setPluginEnabled(CodexPlugin plugin, bool enabled) async {
    if (!plugin.installed) return;
    final operation = _configWriteQueue.then(
      (_) => _writePluginEnabled(plugin, enabled),
    );
    _configWriteQueue = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  /// 串行且原子地写入插件启用状态，避免应用内并发操作损坏配置文件。
  /// Serially and atomically writes plugin state to prevent in-app concurrent operations from corrupting the config file.
  Future<void> _writePluginEnabled(CodexPlugin plugin, bool enabled) async {
    final config = File(
      '${(_codexHome ?? _defaultCodexHome()).path}/config.toml',
    );
    final current = await config.exists() ? await config.readAsString() : '';
    final next = _replaceEnabledValue(current, plugin.id, enabled);
    final writeTarget = await _configWriteTarget(config);
    await writeTarget.parent.create(recursive: true);
    final temporary = File(
      '${writeTarget.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(next, flush: true);
      await temporary.rename(writeTarget.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// 返回配置写入的实际目标，保留用户通过符号链接维护的 `config.toml`。
  /// Returns the actual config write target while preserving a user-managed `config.toml` symlink.
  Future<File> _configWriteTarget(File config) async {
    final type = await FileSystemEntity.type(config.path, followLinks: false);
    if (type != FileSystemEntityType.link) return config;
    return File(await Link(config.path).resolveSymbolicLinks());
  }

  /// 执行 CLI 子命令并将失败信息转换为可展示的错误。
  /// Runs a CLI subcommand and converts failures into displayable errors.
  Future<String> _run(List<String> arguments) async {
    // The executable provider may scan PATH entries asynchronously. Keep that
    // work inside the same bounded user-visible operation as the CLI command.
    final executable = await Future<String>.sync(
      _executableProvider,
    ).timeout(_commandTimeout);
    final result = await _processRunner(
      executable,
      arguments,
    ).timeout(_commandTimeout);
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
      r'[ \t]*(?:#.*)?$',
      multiLine: true,
    ).firstMatch(config);
    final line = 'enabled = $enabled';
    if (headerMatch == null) {
      if (config.isEmpty) return '$header\n$line\n';
      final separator = config.endsWith('\n') ? '' : '\n';
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
      r'^([ \t]*enabled[ \t]*=[ \t]*)(?:true|false)([ \t]*(?:#.*)?)$',
      multiLine: true,
    ).firstMatch(table);
    if (enabledMatch != null) {
      final replacement =
          '${enabledMatch.group(1)}$enabled${enabledMatch.group(2)}';
      return '${config.substring(0, headerMatch.end + enabledMatch.start)}$replacement${config.substring(headerMatch.end + enabledMatch.end)}';
    }
    return '${config.substring(0, headerMatch.end)}\n$line${config.substring(headerMatch.end)}';
  }

  /// 返回默认 Codex CLI 可执行文件名称。
  /// Returns the default Codex CLI executable name.
  static String _defaultExecutable() =>
      Platform.environment['CODEX_EXECUTABLE'] ?? 'codex';

  /// 不经 Shell 执行默认 Codex CLI 子进程。
  /// Runs the default Codex CLI subprocess without a shell.
  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments, runInShell: false);

  /// 返回当前 Codex 用户配置目录，优先使用 `CODEX_HOME`。
  /// Returns the current Codex user configuration directory, preferring `CODEX_HOME`.
  static Directory _defaultCodexHome() {
    final codexHome = Platform.environment['CODEX_HOME'];
    if (codexHome != null && codexHome.isNotEmpty) {
      return Directory(codexHome);
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) throw StateError('无法确定 macOS 用户目录。');
    return Directory('$home/.codex');
  }
}
