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
    this.error,
  });

  final bool isAvailable;
  final String? executablePath;
  final String? version;
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

  /// A non-null value means App Server initiated a JSON-RPC request that the
  /// client must answer. Notifications never carry an id.
  final Object? requestId;

  bool get isServerRequest => requestId != null;
}

/// Boundary around `codex app-server --listen stdio://`.
///
/// App Server speaks newline-delimited JSON-RPC. Keeping it here prevents raw
/// protocol maps from leaking into Flutter widgets.
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
  bool _disposed = false;
  final Set<Process> _stoppedProcesses = {};

  Stream<ServerEvent> get events => _events.stream;
  bool get isRunning => _process != null;
  String get executable => _executable;

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

  Future<CodexRuntimeProbe> probe() async {
    final resolvedExecutable = await _findExecutable();
    if (resolvedExecutable == null) {
      return const CodexRuntimeProbe(
        isAvailable: false,
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
          error: _redact(result.stderr.toString().trim()),
        );
      }
      return CodexRuntimeProbe(
        isAvailable: true,
        executablePath: resolvedExecutable,
        version: result.stdout.toString().trim(),
      );
    } catch (error) {
      return CodexRuntimeProbe(
        isAvailable: false,
        executablePath: resolvedExecutable,
        error: _redact(error.toString()),
      );
    }
  }

  Future<void> start({
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (_disposed) throw StateError('The Codex runtime has been disposed.');
    if (_process != null) return;

    final resolvedExecutable = await _resolveExecutable();
    final process = await Process.start(
      resolvedExecutable,
      const ['app-server', '--listen', 'stdio://'],
      workingDirectory: workingDirectory,
      environment: environment == null
          ? null
          : {...Platform.environment, ...environment},
      runInShell: false,
    );
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

  Future<void> initialize() async {
    final response = await request('initialize', {
      'clientInfo': {
        'name': 'chatgpt_flutter',
        'title': 'Codex Desk',
        'version': '0.1.0',
      },
    });
    _throwIfError(response);
    notify('initialized');
  }

  Future<String> startThread({
    required String workingDirectory,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    final response = await request('thread/start', {
      'cwd': workingDirectory,
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

  Future<void> startTurn({
    required String threadId,
    required String prompt,
    required String workingDirectory,
  }) async {
    final response = await request('turn/start', {
      'threadId': threadId,
      'cwd': workingDirectory,
      'input': [
        {'type': 'text', 'text': prompt},
      ],
    });
    _throwIfError(response);
  }

  Future<void> interruptTurn({required String threadId}) async {
    final response = await request('turn/interrupt', {'threadId': threadId});
    _throwIfError(response);
  }

  Future<List<JsonMap>> listThreads({required String workingDirectory}) async {
    final response = await request('thread/list', {
      'cwd': workingDirectory,
      'limit': 50,
      'sortKey': 'updated_at',
      'sortDirection': 'desc',
    });
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map || result['data'] is! Iterable) {
      throw const FormatException('App Server did not return thread history.');
    }
    return (result['data'] as Iterable)
        .whereType<Map>()
        .map(JsonMap.from)
        .toList(growable: false);
  }

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

  Future<void> archiveThread({required String threadId}) async {
    final response = await request('thread/archive', {'threadId': threadId});
    _throwIfError(response);
  }

  Future<JsonMap> readAccount() async {
    final response = await request('account/read', {'refreshToken': false});
    _throwIfError(response);
    final result = response['result'];
    if (result is! Map) {
      throw const FormatException('App Server did not return account details.');
    }
    return JsonMap.from(result);
  }

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

  Future<void> loginWithApiKey(String apiKey) async {
    final response = await request('account/login/start', {
      'type': 'apiKey',
      'apiKey': apiKey,
    });
    _throwIfError(response);
  }

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

  void notify(String method, [JsonMap params = const {}]) {
    _write({'method': method, 'params': params});
  }

  /// Answer a request initiated by App Server, such as a permission approval.
  void respond(Object requestId, JsonMap result) {
    _write({'id': requestId, 'result': result});
  }

  /// Tell App Server that this client does not support a server request.
  void respondError(Object requestId, String message) {
    _write({
      'id': requestId,
      'error': {'code': -32601, 'message': message},
    });
  }

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
  void handleStdoutLineForTesting(String line) => _handleStdoutLine(line);

  void _throwIfError(JsonMap response) {
    final error = response['error'];
    if (error is Map) {
      final message =
          error['message']?.toString() ?? 'Unknown App Server error.';
      throw StateError(_redact(message));
    }
  }

  void _failPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  String _redact(String value) => value
      .replaceAll(
        RegExp(r'Bearer\s+[^\s]+', caseSensitive: false),
        'Bearer ***',
      )
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]+'), 'sk-***');

  void _emit(ServerEvent event) {
    if (!_disposed && !_events.isClosed) {
      _events.add(event);
    }
  }

  Future<String> _resolveExecutable() async {
    final executable = await _findExecutable();
    if (executable != null) return executable;
    throw StateError('未找到 Codex CLI。请安装 Codex 或手动选择可执行文件。');
  }

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

  Future<void> stop() async {
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

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _events.close();
  }
}
