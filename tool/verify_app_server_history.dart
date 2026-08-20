import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

/// Verifies the real App Server history protocol without creating a thread,
/// sending a turn, or changing files in the selected workspace.
/// 验证真实 App Server 的历史协议，不创建任务或修改工作区文件。
/// Verifies the real App Server history protocol without creating tasks or modifying workspace files.
Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final executable = _findCodexExecutable();
  final process = await Process.start(
    executable,
    const ['app-server', '--listen', 'stdio://'],
    workingDirectory: options.workingDirectory,
    runInShell: false,
  );
  final probe = _AppServerProbe(process);

  try {
    await probe.initialize();
    final listed = await probe.request('thread/list', {
      'cwd': options.workingDirectory,
      'limit': 1,
      'sortKey': 'updated_at',
      'sortDirection': 'desc',
    });
    final threads =
        (listed['data'] as Iterable?)?.whereType<Map>().toList() ??
        const <Map>[];
    if (threads.isEmpty && options.threadId == null) {
      stdout.writeln(
        'App Server is ready; this workspace has no history to resume.',
      );
      return;
    }

    final threadId = options.threadId ?? threads.first['id']?.toString();
    if (threadId == null || threadId.isEmpty) {
      throw const FormatException(
        'The selected thread does not contain an id.',
      );
    }
    final resumed = await probe.request('thread/resume', {
      'threadId': threadId,
      'excludeTurns': true,
    });
    var cursor = <String?>[null];
    final seenCursors = <String>{};
    var pageCount = 0;
    var turnCount = 0;
    while (cursor.isNotEmpty) {
      final page = await probe.request('thread/turns/list', {
        'threadId': threadId,
        'cursor': ?cursor.single,
        'limit': 50,
        'sortDirection': 'desc',
        'itemsView': 'full',
      });
      final turns = page['data'] as Iterable?;
      turnCount += turns?.length ?? 0;
      pageCount++;
      final nextCursor = page['nextCursor']?.toString();
      if (nextCursor == null || nextCursor.isEmpty) {
        cursor = const [];
      } else if (!seenCursors.add(nextCursor)) {
        throw StateError(
          'App Server repeated a thread turns pagination cursor.',
        );
      } else {
        cursor = [nextCursor];
      }
    }
    stdout.writeln(
      'Verified thread $threadId: resumed successfully; '
      '$pageCount turn page(s) contain $turnCount turn(s). '
      'Model provider: ${resumed['modelProvider'] ?? 'unknown'}.',
    );
  } finally {
    await probe.dispose();
  }
}

class _Options {
  const _Options({required this.workingDirectory, this.threadId});

  final String workingDirectory;
  final String? threadId;

  static _Options parse(List<String> arguments) {
    String? cwd;
    String? threadId;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--cwd':
          cwd = _argumentValue(arguments, ++index);
        case '--thread-id':
          threadId = _argumentValue(arguments, ++index);
        default:
          throw ArgumentError(
            'Usage: dart run tool/verify_app_server_history.dart '
            '[--cwd <directory>] [--thread-id <id>]',
          );
      }
    }
    return _Options(
      workingDirectory: cwd ?? Directory.current.path,
      threadId: threadId,
    );
  }

  /// 读取紧随命令行选项后的参数值，缺失时抛出格式错误。
  /// Reads the value following a command-line option or throws on absence.
  static String _argumentValue(List<String> arguments, int index) {
    if (index >= arguments.length || arguments[index].startsWith('--')) {
      throw ArgumentError(
        'Usage: dart run tool/verify_app_server_history.dart '
        '[--cwd <directory>] [--thread-id <id>]',
      );
    }
    return arguments[index];
  }
}

class _AppServerProbe {
  _AppServerProbe(Process process)
    : _process = process,
      _lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );

  final Process _process;
  final StreamIterator<String> _lines;
  var _requestId = 1;

  /// 启动 app-server 子进程并完成 JSON-RPC 初始化握手。
  /// Starts the app-server child process and completes the JSON-RPC handshake.
  Future<void> initialize() async {
    await request('initialize', {
      'clientInfo': {
        'name': 'codex_desk_history_probe',
        'title': 'Codex Desk History Probe',
        'version': '0.1.0',
      },
    });
    _write({'method': 'initialized', 'params': {}});
  }

  /// 发送一个 JSON-RPC 请求并等待带相同 ID 的响应。
  /// Sends a JSON-RPC request and waits for the response with the same ID.
  Future<JsonMap> request(String method, JsonMap params) async {
    final id = _requestId++;
    _write({'id': id, 'method': method, 'params': params});
    while (await _lines.moveNext().timeout(const Duration(seconds: 20))) {
      final decoded = jsonDecode(_lines.current);
      if (decoded is! Map || decoded['id'] != id) continue;
      final response = JsonMap.from(decoded);
      final error = response['error'];
      if (error is Map) {
        throw StateError(error['message']?.toString() ?? 'App Server error.');
      }
      final result = response['result'];
      if (result is! Map) {
        throw FormatException('App Server returned no result for $method.');
      }
      return JsonMap.from(result);
    }
    throw StateError('App Server closed before responding to $method.');
  }

  /// 将一条 JSON-RPC 消息写入 app-server 的标准输入。
  /// Writes one JSON-RPC message to app-server standard input.
  void _write(JsonMap message) => _process.stdin.writeln(jsonEncode(message));

  /// 终止验证过程中启动的 app-server 子进程。
  /// Terminates the app-server child process started for verification.
  Future<void> dispose() async {
    await _lines.cancel();
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
    }
  }
}

/// 按环境变量、常见安装位置和 PATH 查找 Codex CLI。
/// Finds Codex CLI by environment variable, common install locations, and PATH.
String _findCodexExecutable() {
  final configured = Platform.environment['CODEX_EXECUTABLE'];
  if (configured != null && configured.trim().isNotEmpty) return configured;
  for (final candidate in const [
    '/Applications/ChatGPT.app/Contents/Resources/codex',
    '/Applications/Codex.app/Contents/Resources/codex',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return 'codex';
}
