import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef JsonMap = Map<String, dynamic>;

class CodexRuntimeProbe {
  const CodexRuntimeProbe({
    required this.isAvailable,
    this.executablePath,
    this.version,
    this.discovery,
    this.error,
  });

  final bool isAvailable;
  final String? executablePath;
  final String? version;
  final String? discovery;
  final String? error;
}

class ServerEvent {
  const ServerEvent({
    required this.method,
    required this.params,
    this.requestId,
  });

  final String method;
  final JsonMap params;

  /// 非空值表示 App Server 发起了需要客户端答复的 JSON-RPC 请求；通知永远没有 id。
  /// A non-null value means App Server initiated a JSON-RPC request that the client must answer; notifications never carry an id.
  final Object? requestId;

  /// 判断事件是否为需要客户端回复的服务器请求。
  /// Determines whether this event is a server request requiring a client reply.
  bool get isServerRequest => requestId != null;
}

/// `codex app-server --listen stdio://` 的协议边界，负责隔离逐行 JSON-RPC，避免原始协议 Map 泄漏到 Flutter Widget。
/// Boundary around `codex app-server --listen stdio://`; it isolates newline-delimited JSON-RPC so raw protocol maps do not leak into Flutter widgets.
class CodexAppServer {
  CodexAppServer({
    String? executable,
    @visibleForTesting void Function(JsonMap message)? messageSink,
  }) : _messageSink = messageSink,
       _executable =
           executable ?? Platform.environment['CODEX_EXECUTABLE'] ?? 'codex';

  String _executable;
  final void Function(JsonMap message)? _messageSink;
  final StreamController<ServerEvent> _events =
      StreamController<ServerEvent>.broadcast();
  final Map<int, Completer<JsonMap>> _pending = {};

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  int _nextRequestId = 1;
  // stop/dispose 会推进代次，取消仍停留在可执行文件解析或进程创建阶段的 start。
  // stop/dispose advances this epoch to cancel start calls still resolving or spawning a process.
  int _lifecycleEpoch = 0;
  bool _disposed = false;
  // 主动停止的进程不应再向控制器发布意外 runtime/exited 事件。
  // Processes stopped by the client must not emit an unexpected runtime/exited event.
  final Set<Process> _stoppedProcesses = {};

  /// 返回 App Server 通知及请求组成的广播事件流。
  /// Returns the broadcast stream of App Server notifications and requests.
  Stream<ServerEvent> get events => _events.stream;

  /// 判断本地 App Server 子进程是否正在运行。
  /// Determines whether the local App Server process is running.
  bool get isRunning => _process != null;

  /// 返回当前将被启动或探测的 Codex CLI 路径。
  /// Returns the Codex CLI path currently selected for launch or probing.
  String get executable => _executable;

  /// 解析当前配置为可直接执行的 Codex CLI 路径。
  /// Resolves the current configuration to an executable Codex CLI path.
  Future<String> resolveExecutable() => _resolveExecutable();

  /// 设置 CLI 路径；运行时启动后禁止修改以避免进程不一致。
  /// Sets the CLI path; changes are prohibited while running to avoid process inconsistency.
  void setExecutable(String? executable) {
    if (isRunning) {
      throw StateError(
        'Stop the Codex runtime before changing its executable.',
      );
    }
    _executable = executable?.trim().isNotEmpty == true
        ? executable!.trim()
        : Platform.environment['CODEX_EXECUTABLE'] ?? 'codex';
  }

  /// 定位 CLI 并执行版本命令，返回可用性诊断信息。
  /// Locates the CLI and runs its version command, returning availability diagnostics.
  Future<CodexRuntimeProbe> probe() async {
    final resolvedExecutable = await _findExecutable();
    if (resolvedExecutable == null) {
      return const CodexRuntimeProbe(
        isAvailable: false,
        discovery: '自动查找：已检查用户设置、常见安装位置和 PATH。',
        error: '未找到 Codex CLI。请安装 Codex 或手动选择可执行文件。',
      );
    }
    try {
      final result = await Process.run(resolvedExecutable, const [
        '--version',
      ], runInShell: false).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) {
        return CodexRuntimeProbe(
          isAvailable: false,
          executablePath: resolvedExecutable,
          discovery: _executableDiscovery,
          error: _redact(result.stderr.toString().trim()),
        );
      }
      return CodexRuntimeProbe(
        isAvailable: true,
        executablePath: resolvedExecutable,
        version: result.stdout.toString().trim(),
        discovery: _executableDiscovery,
      );
    } catch (error) {
      return CodexRuntimeProbe(
        isAvailable: false,
        executablePath: resolvedExecutable,
        discovery: _executableDiscovery,
        error: _redact(error.toString()),
      );
    }
  }

  /// 以指定项目目录启动本地 App Server 并订阅其标准输出和错误流。
  /// Starts local App Server for a workspace and subscribes to its stdout and stderr.
  Future<void> start({required String workingDirectory}) async {
    if (_disposed) throw StateError('The Codex runtime has been disposed.');
    if (_process != null) return;

    final lifecycleEpoch = _lifecycleEpoch;
    final resolvedExecutable = await _resolveExecutable();
    if (_disposed || lifecycleEpoch != _lifecycleEpoch) {
      throw StateError('The Codex runtime start was cancelled.');
    }
    final process = await Process.start(
      resolvedExecutable,
      const ['app-server', '--listen', 'stdio://'],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    if (_disposed || lifecycleEpoch != _lifecycleEpoch) {
      // Process.start 无法中途取消，因此创建完成后再校验代次并立即回收。
      // Process.start is not cancellable, so validate the epoch after spawn and reclaim if stale.
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
      throw StateError('The Codex runtime start was cancelled.');
    }
    _process = process;

    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _emit(
            ServerEvent(
              method: 'runtime/stderr',
              params: {'message': _redact(line)},
            ),
          ),
        );

    unawaited(
      process.exitCode.then((code) {
        final stoppedByClient = _stoppedProcesses.remove(process);
        if (identical(_process, process)) {
          _process = null;
        }
        if (!stoppedByClient) {
          _emit(ServerEvent(method: 'runtime/exited', params: {'code': code}));
          _failPending(StateError('Codex runtime exited with code $code.'));
        }
      }),
    );
  }

  /// 完成 JSON-RPC 初始化握手并发送 `initialized` 通知。
  /// Completes the JSON-RPC initialization handshake and sends `initialized`.
  Future<void> initialize() async {
    final response = await request('initialize', {
      'clientInfo': {
        'name': 'chatgpt_flutter',
        'title': 'Codex Desk',
        'version': '0.1.0',
      },
      // `thread/start.runtimeWorkspaceRoots` is an experimental App Server
      // field. Opt in during the handshake so additional workspace directories
      // can be passed to newly created threads without a protocol rejection.
      'capabilities': {'experimentalApi': true},
    });
    _throwIfError(response);
    notify('initialized');
  }

  /// 返回已连接 App Server 暴露给选择器的所有模型，条目包含支持的推理强度。
  /// Returns every picker-visible model exposed by the connected App Server; entries include supported reasoning efforts.
  Future<List<JsonMap>> listModels({bool includeHidden = false}) async {
    final models = <JsonMap>[];
    final seenCursors = <String>{};
    String? cursor;
    do {
      final response = await request('model/list', {
        'cursor': ?cursor,
        'includeHidden': includeHidden,
      });
      _throwIfError(response);
      final result = response['result'];
      if (result is! Map || result['data'] is! Iterable) {
        throw const FormatException('App Server did not return model options.');
      }
      models.addAll(
        (result['data'] as Iterable).whereType<Map>().map(JsonMap.from),
      );
      final next = result['nextCursor']?.toString();
      cursor = next == null || next.isEmpty ? null : next;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw StateError('App Server repeated a model list pagination cursor.');
      }
    } while (cursor != null);
    return models;
  }

  /// 读取指定项目最终生效的 Codex 配置；返回值由 App Server 按官方配置层级合并。
  /// Reads the effective Codex configuration for a workspace after App Server applies the official layer precedence.
  Future<JsonMap> readConfig({String? workingDirectory}) async {
    final response = await request('config/read', {
      'cwd': ?workingDirectory,
      'includeLayers': false,
    });
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map || result['config'] is! Map) {
      throw const FormatException(
        'App Server did not return the effective Codex configuration.',
      );
    }
    return JsonMap.from(result);
  }

  /// 在指定项目中创建线程，并返回服务器分配的线程 ID。
  /// Creates a thread in a workspace and returns the server-assigned thread ID.
  Future<String> startThread({
    required String workingDirectory,
    List<String>? runtimeWorkspaceRoots,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    final response = await request('thread/start', {
      'cwd': workingDirectory,
      'runtimeWorkspaceRoots': ?runtimeWorkspaceRoots,
      'modelProvider': ?modelProvider,
      'model': ?model,
      'config': ?config,
    });
    _throwIfError(response);
    final result = JsonMap.from(response['result'] as Map);
    final thread = JsonMap.from(result['thread'] as Map);
    final id = thread['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('App Server did not return a thread id.');
    }
    return id;
  }

  /// 在现有线程中开始一次文本任务。
  /// Starts a text task in an existing thread.
  Future<void> startTurn({
    required String threadId,
    required String prompt,
    required String workingDirectory,
    List<JsonMap> additionalInput = const [],
    JsonMap? collaborationMode,
  }) async {
    final response = await request('turn/start', {
      'threadId': threadId,
      'cwd': workingDirectory,
      'input': [
        {'type': 'text', 'text': prompt},
        ...additionalInput,
      ],
      'collaborationMode': ?collaborationMode,
    });
    _throwIfError(response);
  }

  /// Steers the currently active turn without starting a second turn.
  /// Sends a user correction to the App Server's `turn/steer` endpoint.
  Future<String> steerTurn({
    required String threadId,
    required String expectedTurnId,
    required String prompt,
    List<JsonMap> additionalInput = const [],
  }) async {
    final response = await request('turn/steer', {
      'threadId': threadId,
      'expectedTurnId': expectedTurnId,
      'input': [
        {'type': 'text', 'text': prompt},
        ...additionalInput,
      ],
    });
    _throwIfError(response);
    final result = response['result'];
    final turnId = result is Map ? result['turnId']?.toString().trim() : null;
    if (turnId == null || turnId.isEmpty) {
      throw const FormatException(
        'App Server did not return the steered turn id.',
      );
    }
    return turnId;
  }

  /// Sets or replaces the persistent objective for a thread.
  Future<void> setThreadGoal({
    required String threadId,
    required String objective,
  }) async {
    final response = await request('thread/goal/set', {
      'threadId': threadId,
      'objective': objective,
      'status': 'active',
    });
    _throwIfError(response);
  }

  /// Lists the skills available to the current workspace.
  Future<List<JsonMap>> listSkills({
    required String workingDirectory,
    bool forceReload = false,
  }) async {
    final response = await request('skills/list', {
      'cwds': [workingDirectory],
      'forceReload': forceReload,
    });
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map || result['data'] is! Iterable) {
      throw const FormatException('App Server did not return a skill list.');
    }
    for (final rawEntry in result['data'] as Iterable) {
      if (rawEntry is! Map) continue;
      final entry = JsonMap.from(rawEntry);
      if (entry['cwd']?.toString() != workingDirectory) continue;
      final rawSkills = entry['skills'];
      if (rawSkills is! Iterable) return const [];
      return rawSkills
          .whereType<Map>()
          .map((skill) => JsonMap.from(skill))
          .toList(growable: false);
    }
    return const [];
  }

  /// 请求中断指定线程正在执行的任务。
  /// Requests interruption of the executing task in a thread.
  Future<void> interruptTurn({
    required String threadId,
    required String turnId,
  }) async {
    final response = await request('turn/interrupt', {
      'threadId': threadId,
      'turnId': turnId,
    });
    _throwIfError(response);
  }

  /// 分页获取一个项目的活跃或归档线程，检测重复游标。
  /// Paginates active or archived threads for a workspace and detects repeated cursors.
  Future<List<JsonMap>> listThreads({
    required String workingDirectory,
    bool archived = false,
  }) async {
    final threads = <JsonMap>[];
    final seenCursors = <String>{};
    String? cursor;
    do {
      final response = await request('thread/list', {
        'cwd': workingDirectory,
        'cursor': ?cursor,
        'limit': 50,
        'sortKey': 'updated_at',
        'sortDirection': 'desc',
        if (archived) 'archived': true,
      });
      _throwIfError(response);
      final result = response['result'];
      if (result is! Map || result['data'] is! Iterable) {
        throw const FormatException(
          'App Server did not return thread history.',
        );
      }
      threads.addAll(
        (result['data'] as Iterable).whereType<Map>().map(JsonMap.from),
      );
      final next = result['nextCursor']?.toString();
      cursor = next == null || next.isEmpty ? null : next;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw StateError(
          'App Server repeated a thread list pagination cursor.',
        );
      }
    } while (cursor != null);
    return threads;
  }

  /// 恢复指定线程，并返回服务器提供的初始历史数据。
  /// Resumes a thread and returns its server-provided initial history data.
  Future<JsonMap> resumeThread({
    required String threadId,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    final response = await request('thread/resume', {
      'threadId': threadId,
      'modelProvider': ?modelProvider,
      'model': ?model,
      'config': ?config,
    });
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map) {
      throw const FormatException(
        'App Server did not return resumed thread history.',
      );
    }
    return JsonMap.from(result);
  }

  /// 获取线程历史 turn 的一页完整视图数据。
  /// Fetches one full-view page of historic turns for a thread.
  Future<JsonMap> listThreadTurns({
    required String threadId,
    String? cursor,
    int limit = 50,
    String sortDirection = 'desc',
  }) async {
    final response = await request('thread/turns/list', {
      'threadId': threadId,
      'cursor': ?cursor,
      'limit': limit,
      'sortDirection': sortDirection,
      'itemsView': 'full',
    });
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map || result['data'] is! Iterable) {
      throw const FormatException('App Server did not return thread turns.');
    }
    return JsonMap.from(result);
  }

  /// 获取指定 turn 中历史项目的一页数据。
  /// Fetches one page of historic items in a specified turn.
  Future<JsonMap> listThreadItems({
    required String threadId,
    required String turnId,
    String? cursor,
    int limit = 50,
  }) async {
    final response = await request('thread/items/list', {
      'threadId': threadId,
      'turnId': turnId,
      'cursor': ?cursor,
      'limit': limit,
      'sortDirection': 'asc',
    });
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map || result['data'] is! Iterable) {
      throw const FormatException('App Server did not return thread items.');
    }
    return JsonMap.from(result);
  }

  /// 在 App Server 中设置线程名称。
  /// Sets a thread name in App Server.
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    final response = await request('thread/name/set', {
      'threadId': threadId,
      'name': name,
    });
    _throwIfError(response);
  }

  /// 在 App Server 中归档线程。
  /// Archives a thread in App Server.
  Future<void> archiveThread({required String threadId}) async {
    final response = await request('thread/archive', {'threadId': threadId});
    _throwIfError(response);
  }

  /// 在 App Server 中永久删除线程及其派生线程。
  /// Permanently deletes a thread and its spawned descendants in App Server.
  Future<void> deleteThread({required String threadId}) async {
    final response = await request('thread/delete', {'threadId': threadId});
    _throwIfError(response);
  }

  /// 在 App Server 中恢复归档线程。
  /// Unarchives a thread in App Server.
  Future<void> unarchiveThread({required String threadId}) async {
    final response = await request('thread/unarchive', {'threadId': threadId});
    _throwIfError(response);
  }

  /// 读取当前 App Server 的账户认证与套餐信息。
  /// Reads authentication and plan information from the current App Server.
  Future<JsonMap> readAccount() async {
    final response = await request('account/read', {'refreshToken': false});
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map) {
      throw const FormatException('App Server did not return account details.');
    }
    return JsonMap.from(result);
  }

  /// 请求由浏览器完成的 ChatGPT 登录流程。
  /// Requests the browser-completed ChatGPT login flow.
  Future<JsonMap> startChatgptLogin() async {
    final response = await request('account/login/start', {
      'type': 'chatgpt',
      'useHostedLoginSuccessPage': true,
      'appBrand': 'chatgpt',
    });
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map) {
      throw const FormatException('App Server did not return a login URL.');
    }
    return JsonMap.from(result);
  }

  /// 将 API Key 提交给当前本地 App Server 进行认证。
  /// Submits an API key to the current local App Server for authentication.
  Future<void> loginWithApiKey(String apiKey) async {
    final response = await request('account/login/start', {
      'type': 'apiKey',
      'apiKey': apiKey,
    });
    _throwIfError(response);
  }

  /// 发送带 ID 的 JSON-RPC 请求，并在超时前等待匹配响应。
  /// Sends an ID-bearing JSON-RPC request and waits for its matching response before timeout.
  Future<JsonMap> request(String method, [JsonMap params = const {}]) {
    final process = _process;
    if (process == null) throw StateError('The Codex runtime is not running.');

    final id = _nextRequestId++;
    final completer = Completer<JsonMap>();
    _pending[id] = completer;
    _write({'method': method, 'id': id, 'params': params});
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('Timed out waiting for $method.');
      },
    );
  }

  /// 发送不期待响应的 JSON-RPC 通知。
  /// Sends a JSON-RPC notification that does not expect a response.
  void notify(String method, [JsonMap params = const {}]) {
    _write({'method': method, 'params': params});
  }

  /// 回答 App Server 主动发起的请求，例如权限审批。
  /// Answers a request initiated by App Server, such as a permission approval.
  void respond(Object requestId, JsonMap result) {
    _write({'id': requestId, 'result': result});
  }

  /// 告知 App Server 此客户端不支持某个服务器请求。
  /// Tells App Server that this client does not support a server request.
  void respondError(Object requestId, String message) {
    _write({
      'id': requestId,
      'error': {'code': -32601, 'message': message},
    });
  }

  /// 通过测试注入接收器或运行时标准输入写出一条协议消息。
  /// Writes a protocol message through the test sink or runtime standard input.
  void _write(JsonMap message) {
    final messageSink = _messageSink;
    if (messageSink != null) {
      messageSink(message);
      return;
    }
    final process = _process;
    if (process == null) throw StateError('The Codex runtime is not running.');
    process.stdin.writeln(jsonEncode(message));
  }

  /// 解析 App Server 输出的一行 JSON-RPC，分发事件或完成等待中的请求。
  /// Parses one App Server JSON-RPC line, dispatching an event or completing a pending request.
  void _handleStdoutLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      final message = JsonMap.from(decoded);
      final id = message['id'];
      final method = message['method'];

      // JSON-RPC is bidirectional: server requests contain both a method and
      // an id, while responses only contain an id. Classify requests first so
      // approval prompts cannot be mistaken for responses to our own calls.
      if (method is String) {
        final rawParams = message['params'];
        _emit(
          ServerEvent(
            method: method,
            params: rawParams is Map ? JsonMap.from(rawParams) : const {},
            requestId: id is String || id is num ? id : null,
          ),
        );
        return;
      }

      if (id is num) {
        final completer = _pending.remove(id.toInt());
        if (completer != null && !completer.isCompleted) {
          completer.complete(message);
        }
      }
    } catch (_) {
      _emit(
        ServerEvent(
          method: 'runtime/invalidMessage',
          params: {'message': _redact(line)},
        ),
      );
    }
  }

  @visibleForTesting
  /// 注入一行服务器输出，供协议解析测试使用。
  /// Injects one server-output line for protocol parsing tests.
  void handleStdoutLineForTesting(String line) => _handleStdoutLine(line);

  /// 将 JSON-RPC 错误响应转换为脱敏的 Dart 状态错误。
  /// Converts a JSON-RPC error response into a redacted Dart state error.
  void _throwIfError(JsonMap response) {
    final error = response['error'];
    if (error is Map) {
      final message =
          error['message']?.toString() ?? 'Unknown App Server error.';
      throw StateError(_redact(message));
    }
  }

  /// 以相同错误完成所有尚未响应的客户端请求。
  /// Completes every unresolved client request with the same error.
  void _failPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  /// 从诊断文本中隐藏 Bearer/Basic 凭据、常见 API Key 和凭据字段。
  /// Redacts Bearer/Basic credentials, common API keys, and credential fields from diagnostic text.
  static String redactDiagnosticText(String value) => value
      .replaceAllMapped(
        RegExp(
          r'(\bAuthorization\s*[:=]\s*)(?:Bearer|Basic)\s+[^\s,;}\]"]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}***',
      )
      .replaceAll(
        RegExp(r'Bearer\s+[^\s]+', caseSensitive: false),
        'Bearer ***',
      )
      .replaceAllMapped(
        RegExp(
          r'((?:"?(?:api[_-]?key|authorization|token|password|secret)"?)\s*[=:]\s*"?)[^\s,;}\]"]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}***',
      )
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]+'), 'sk-***');

  /// 复用公开脱敏规则，避免日志、协议错误和探测错误处理不一致。
  /// Reuses the public redaction rules so logs, protocol errors, and probe errors stay consistent.
  String _redact(String value) => redactDiagnosticText(value);

  /// 返回当前可执行文件查找策略的可展示说明，不输出完整 PATH 内容。
  /// Returns a displayable executable-discovery summary without exposing full PATH contents.
  String get _executableDiscovery =>
      executable.contains('/') ? '使用本应用配置的可执行文件路径。' : '自动查找：用户设置、常见安装位置和 PATH。';

  /// 在未释放状态下向订阅者发布服务器事件。
  /// Publishes a server event to subscribers while the client remains active.
  void _emit(ServerEvent event) {
    if (!_disposed && !_events.isClosed) {
      _events.add(event);
    }
  }

  /// 解析 CLI 路径；找不到时抛出可展示的状态错误。
  /// Resolves the CLI path or throws a displayable state error when absent.
  Future<String> _resolveExecutable() async {
    final executable = await _findExecutable();
    if (executable != null) return executable;
    throw StateError('未找到 Codex CLI。请安装 Codex 或手动选择可执行文件。');
  }

  /// 按用户设置、常见安装路径和 PATH 顺序查找 Codex CLI。
  /// Finds Codex CLI by user setting, common install paths, then PATH order.
  Future<String?> _findExecutable() async {
    final requested = executable;
    if (requested.contains('/')) {
      return await File(requested).exists() ? requested : null;
    }
    final home = Platform.environment['HOME'];
    final pathDirectories = (Platform.environment['PATH'] ?? '')
        .split(Platform.pathSeparator)
        .where((directory) => directory.isNotEmpty);
    final candidates = <String>[
      '/Applications/ChatGPT.app/Contents/Resources/codex',
      '/Applications/Codex.app/Contents/Resources/codex',
      '/opt/homebrew/bin/codex',
      '/usr/local/bin/codex',
      if (home != null)
        '$home/Applications/ChatGPT.app/Contents/Resources/codex',
      if (home != null) '$home/Applications/Codex.app/Contents/Resources/codex',
      if (home != null) '$home/.local/bin/codex',
      if (home != null) '$home/.codex/bin/codex',
      if (home != null) '$home/.npm-global/bin/codex',
      if (home != null) '$home/Library/pnpm/codex',
      if (home != null) '$home/.bun/bin/codex',
      ...pathDirectories.map((directory) => '$directory/codex'),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  /// 取消流订阅、失败化等待请求并终止本地 App Server 进程。
  /// Cancels stream subscriptions, fails pending requests, and terminates local App Server.
  Future<void> stop() async {
    _lifecycleEpoch++;
    _failPending(StateError('Codex runtime stopped.'));
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    final process = _process;
    _process = null;
    if (process == null) return;

    _stoppedProcesses.add(process);
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// 释放 App Server 客户端及其所有进程和事件资源。
  /// Disposes the App Server client and all process and event resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _events.close();
  }
}
