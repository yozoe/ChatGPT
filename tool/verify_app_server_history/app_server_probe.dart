// Extracted App Server history verification helper.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

class AppServerProbe {
  AppServerProbe(Process process)
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
