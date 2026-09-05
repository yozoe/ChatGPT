import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';

/// 可替换的 CLI 执行边界，使插件命令可在测试中脱离真实子进程验证。
/// Replaceable CLI runner boundary for testing plugin commands without real subprocesses.
typedef CodexPluginProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

typedef CodexPluginScopedProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

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
    CodexPluginScopedProcessRunner? scopedProcessRunner,
  }) : _executableProvider = executableProvider ?? _defaultExecutable,
       _codexHome = codexHome,
       _usesDefaultProcessRunner =
           processRunner == null && scopedProcessRunner == null,
       _processRunner = processRunner ?? _defaultProcessRunner,
       _scopedProcessRunner =
           scopedProcessRunner ??
           (processRunner == null
               ? _defaultScopedProcessRunner
               : (executable, arguments, _) =>
                     processRunner(executable, arguments));

  final CodexPluginExecutableProvider _executableProvider;
  final Directory? _codexHome;
  final bool _usesDefaultProcessRunner;
  final CodexPluginProcessRunner _processRunner;
  final CodexPluginScopedProcessRunner _scopedProcessRunner;
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
      final entryMap = Map<String, dynamic>.from(entry);
      final sourcePath = _sourcePath(entryMap['source']);
      final metadata = await _readPluginInterface(sourcePath);
      final logoPath = await _resolveLogoPath(sourcePath, metadata?['logo']);
      final plugin = CodexPlugin.fromJson(
        entryMap,
        interfaceMetadata: metadata,
        sourcePath: sourcePath,
        logoPath: logoPath,
      );
      if (plugin != null) plugins[plugin.id] = plugin;
    }
    return plugins.values.toList(growable: false)..sort((left, right) {
      if (left.installed != right.installed) return left.installed ? -1 : 1;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
  }

  String? _sourcePath(Object? source) {
    if (source is! Map) return null;
    final path = source['path']?.toString().trim();
    return path == null || path.isEmpty ? null : path;
  }

  Future<Map<String, dynamic>?> _readPluginInterface(String? sourcePath) async {
    if (sourcePath == null) return null;
    try {
      final file = File(
        '$sourcePath${Platform.pathSeparator}.codex-plugin${Platform.pathSeparator}plugin.json',
      );
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['interface'] is! Map) return null;
      return Map<String, dynamic>.from(decoded['interface'] as Map);
    } catch (_) {
      // A broken optional presentation manifest must not hide a valid plugin.
      return null;
    }
  }

  Future<String?> _resolveLogoPath(String? sourcePath, Object? logo) async {
    if (sourcePath == null || logo == null) return null;
    final value = logo.toString().trim();
    if (value.isEmpty) return null;
    final relative = value.startsWith('./') ? value.substring(2) : value;
    if (relative.startsWith('/') || relative.startsWith('\\')) return null;
    try {
      final sourceRoot = await Directory(sourcePath).resolveSymbolicLinks();
      final candidate = await File(
        '$sourcePath${Platform.pathSeparator}$relative',
      ).resolveSymbolicLinks();
      final rootPrefix = '$sourceRoot${Platform.pathSeparator}';
      if (!candidate.startsWith(rootPrefix)) return null;
      return candidate;
    } on FileSystemException {
      return null;
    }
  }

  /// 返回当前 Codex 配置中的 MCP 服务器。
  /// Returns MCP servers from the active Codex configuration.
  Future<List<CodexMcpServer>> listMcpServers({
    String? workingDirectory,
  }) async {
    final decoded = jsonDecode(
      await _run(const [
        'mcp',
        'list',
        '--json',
      ], workingDirectory: workingDirectory),
    );
    if (decoded is! Iterable) {
      throw const FormatException('Codex CLI 返回了无效的 MCP 服务器列表。');
    }
    final servers = decoded
        .whereType<Map>()
        .map(
          (value) => CodexMcpServer.fromJson(Map<String, dynamic>.from(value)),
        )
        .whereType<CodexMcpServer>()
        .toList(growable: false);
    final userConfig = _userConfigFile();
    final userContents = await _readConfig(userConfig);
    final projectTrusted =
        workingDirectory != null &&
        _isProjectTrusted(userContents, workingDirectory);
    final projectConfig = workingDirectory == null
        ? null
        : File(
            '$workingDirectory${Platform.pathSeparator}.codex${Platform.pathSeparator}config.toml',
          );
    final projectContents = projectTrusted && projectConfig != null
        ? await _readConfig(projectConfig)
        : '';
    return servers
        .map((server) {
          if (projectConfig != null &&
              _findTableHeader(
                    projectContents,
                    tableNamespace: 'mcp_servers',
                    id: server.name,
                  ) !=
                  null) {
            return server.copyWith(
              scope: CodexMcpServerScope.project,
              configurationPath: projectConfig.path,
            );
          }
          if (_findTableHeader(
                userContents,
                tableNamespace: 'mcp_servers',
                id: server.name,
              ) !=
              null) {
            return server.copyWith(
              scope: CodexMcpServerScope.user,
              configurationPath: userConfig.path,
            );
          }
          return server.copyWith(scope: CodexMcpServerScope.managed);
        })
        .toList(growable: false);
  }

  /// 添加一个 HTTP MCP 服务器。
  /// Adds an HTTP MCP server.
  Future<void> addMcpServer({required String name, required String url}) async {
    final serverName = name.trim();
    final serverUrl = url.trim();
    if (serverName.isEmpty || serverUrl.isEmpty) {
      throw const FormatException('请输入服务器名称和 URL。');
    }
    final uri = Uri.tryParse(serverUrl);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        !uri.hasAuthority) {
      throw const FormatException('请输入有效的 MCP 服务器 URL。');
    }
    await _run(['mcp', 'add', serverName, '--url', serverUrl]);
  }

  /// 更新 MCP 服务器启用状态。
  /// Updates an MCP server enabled state.
  Future<void> setMcpServerEnabled(
    CodexMcpServer server,
    bool enabled, {
    String? workingDirectory,
  }) async {
    if (!server.canChangeEnabled) {
      throw StateError('该 MCP 服务器由插件或其他配置来源管理，无法在此直接启停。');
    }
    final config = await _mcpConfigFileFor(
      server,
      workingDirectory: workingDirectory,
    );
    await _queueConfigFileWrite(
      config,
      (current) => _replaceTableEnabledValue(
        current,
        tableNamespace: 'mcp_servers',
        id: server.name,
        enabled: enabled,
      ),
    );
  }

  /// 更新本地技能启用状态。
  /// Updates a local skill enabled state.
  Future<void> setSkillEnabled(CodexSkill skill, bool enabled) =>
      _queueConfigWrite(
        (current) => _replaceSkillEnabledValue(current, skill.path, enabled),
      );

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
    await _writeConfig(
      (current) => _replaceTableEnabledValue(
        current,
        tableNamespace: 'plugins',
        id: plugin.id,
        enabled: enabled,
      ),
    );
  }

  Future<void> _queueConfigWrite(String Function(String) transform) {
    return _queueConfigFileWrite(_userConfigFile(), transform);
  }

  Future<void> _queueConfigFileWrite(
    File config,
    String Function(String) transform,
  ) {
    final operation = _configWriteQueue.then(
      (_) => _writeConfigFile(config, transform),
    );
    _configWriteQueue = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<void> _writeConfig(String Function(String) transform) async {
    await _writeConfigFile(_userConfigFile(), transform);
  }

  Future<void> _writeConfigFile(
    File config,
    String Function(String) transform,
  ) async {
    final current = await config.exists() ? await config.readAsString() : '';
    final next = transform(current);
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

  File _userConfigFile() => File(
    '${(_codexHome ?? _defaultCodexHome()).path}${Platform.pathSeparator}config.toml',
  );

  Future<String> _readConfig(File config) async =>
      await config.exists() ? config.readAsString() : '';

  Future<File> _mcpConfigFileFor(
    CodexMcpServer server, {
    String? workingDirectory,
  }) async {
    if (server.scope == CodexMcpServerScope.project &&
        workingDirectory == null) {
      throw StateError('缺少当前项目目录，无法安全更新 MCP 服务器 ${server.name}。');
    }
    final userConfig = _userConfigFile();
    final userContents = await _readConfig(userConfig);
    final projectTrusted =
        workingDirectory != null &&
        _isProjectTrusted(userContents, workingDirectory);
    if (server.scope == CodexMcpServerScope.project && !projectTrusted) {
      throw StateError('当前项目配置未受 Codex 信任，无法安全更新 MCP 服务器 ${server.name}。');
    }
    if (workingDirectory != null &&
        projectTrusted &&
        (server.scope != CodexMcpServerScope.user ||
            server.configurationPath == null)) {
      final projectConfig = File(
        '$workingDirectory${Platform.pathSeparator}.codex${Platform.pathSeparator}config.toml',
      );
      if (_findTableHeader(
            await _readConfig(projectConfig),
            tableNamespace: 'mcp_servers',
            id: server.name,
          ) !=
          null) {
        return projectConfig;
      }
      if (server.scope == CodexMcpServerScope.project) {
        throw StateError('当前项目中已找不到 MCP 服务器 ${server.name} 的定义，请刷新列表后重试。');
      }
    }
    if (_findTableHeader(
          userContents,
          tableNamespace: 'mcp_servers',
          id: server.name,
        ) !=
        null) {
      return userConfig;
    }
    throw StateError('找不到 MCP 服务器 ${server.name} 的配置来源，请刷新列表后重试。');
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
  Future<String> _run(
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    // The executable provider may scan PATH entries asynchronously. Keep that
    // work inside the same bounded user-visible operation as the CLI command.
    final executable = await Future<String>.sync(
      _executableProvider,
    ).timeout(_commandTimeout);
    final result = _usesDefaultProcessRunner
        ? await _runManagedProcess(
            executable,
            arguments,
            workingDirectory: workingDirectory,
          )
        : await (workingDirectory == null
                  ? _processRunner(executable, arguments)
                  : _scopedProcessRunner(
                      executable,
                      arguments,
                      workingDirectory,
                    ))
              .timeout(_commandTimeout);
    if (result.exitCode != 0) {
      final detail = result.stderr.toString().trim();
      throw StateError(detail.isEmpty ? 'Codex CLI 插件命令执行失败。' : detail);
    }
    return result.stdout.toString();
  }

  Future<ProcessResult> _runManagedProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final exitCode = await process.exitCode.timeout(_commandTimeout);
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } on TimeoutException {
      await _terminateProcess(process);
      await Future.wait([stdout, stderr]);
      throw TimeoutException('Codex CLI 插件命令执行超时。');
    }
  }

  Future<void> _terminateProcess(Process process) async {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
      return;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }

  /// 在 TOML 中替换或添加指定插件表内的 `enabled` 键。
  /// Replaces or adds the `enabled` key in the target plugin's TOML table.
  String _replaceTableEnabledValue(
    String config, {
    required String tableNamespace,
    required String id,
    required bool enabled,
  }) {
    final escapedId = id.replaceAll('\\', r'\\').replaceAll('"', r'\"');
    final header = '[$tableNamespace."$escapedId"]';
    final headerMatch = _findTableHeader(
      config,
      tableNamespace: tableNamespace,
      id: id,
    );
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

  RegExpMatch? _findTableHeader(
    String config, {
    required String tableNamespace,
    required String id,
  }) {
    final escapedId = id.replaceAll('\\', r'\\').replaceAll('"', r'\"');
    final quotedHeader = '[$tableNamespace."$escapedId"]';
    final bareHeader = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)
        ? '[$tableNamespace.$id]'
        : null;
    final literalHeader = id.contains("'") ? null : "[$tableNamespace.'$id']";
    final headerPattern = [
      quotedHeader,
      ?literalHeader,
      ?bareHeader,
    ].map(RegExp.escape).join('|');
    return RegExp(
      '^(?:$headerPattern)'
      r'[ \t]*(?:#.*)?$',
      multiLine: true,
    ).firstMatch(config);
  }

  bool _isProjectTrusted(String userConfig, String workingDirectory) {
    final projectHeader = _findTableHeader(
      userConfig,
      tableNamespace: 'projects',
      id: workingDirectory,
    );
    if (projectHeader == null) return false;
    final tableEnd = _tableEndAfterHeader(userConfig, projectHeader);
    final body = userConfig.substring(projectHeader.end, tableEnd);
    final trustLevel = RegExp(
      r'''^[ \t]*trust_level[ \t]*=[ \t]*(?:"trusted"|'trusted')[ \t]*(?:#.*)?$''',
      multiLine: true,
    );
    return trustLevel.hasMatch(body);
  }

  int _tableEndAfterHeader(String config, RegExpMatch header) {
    final nextHeaders = RegExp(
      r'^\[',
      multiLine: true,
    ).allMatches(config).where((match) => match.start >= header.end);
    return nextHeaders.isEmpty ? config.length : nextHeaders.first.start;
  }

  String _replaceSkillEnabledValue(
    String config,
    String skillPath,
    bool enabled,
  ) {
    final blocks = RegExp(
      r'^\[\[skills\.config\]\][ \t]*(?:#.*)?$',
      multiLine: true,
    ).allMatches(config).toList(growable: false);
    final headers = RegExp(r'^\[\[?', multiLine: true).allMatches(config);
    for (final block in blocks) {
      final followingHeaders = headers.where(
        (header) => header.start > block.start,
      );
      final end = followingHeaders.isEmpty
          ? config.length
          : followingHeaders.first.start;
      final body = config.substring(block.end, end);
      final pathMatch = RegExp(
        r'''^[ \t]*path[ \t]*=[ \t]*(?:"((?:\\.|[^"\\])*)"|'([^'\r\n]*)')[ \t]*(?:#.*)?$''',
        multiLine: true,
      ).firstMatch(body);
      final basicPath = pathMatch?.group(1);
      final configuredPath = basicPath == null
          ? pathMatch?.group(2)
          : _unescapeToml(basicPath);
      if (configuredPath != skillPath) {
        continue;
      }
      final enabledMatch = RegExp(
        r'^([ \t]*enabled[ \t]*=[ \t]*)(?:true|false)([ \t]*(?:#.*)?)$',
        multiLine: true,
      ).firstMatch(body);
      if (enabledMatch != null) {
        final start = block.end + enabledMatch.start;
        final finish = block.end + enabledMatch.end;
        return '${config.substring(0, start)}${enabledMatch.group(1)}$enabled${enabledMatch.group(2)}${config.substring(finish)}';
      }
      return '${config.substring(0, end).trimRight()}\nenabled = $enabled\n${config.substring(end)}';
    }
    final escapedPath = skillPath
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    final separator = config.isEmpty
        ? ''
        : (config.endsWith('\n') ? '\n' : '\n\n');
    return '$config$separator[[skills.config]]\npath = "$escapedPath"\nenabled = $enabled\n';
  }

  String _unescapeToml(String value) => value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', '\\');

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

  static Future<ProcessResult> _defaultScopedProcessRunner(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) => Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );

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
