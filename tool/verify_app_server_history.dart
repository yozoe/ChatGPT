import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

/// Verifies the real App Server history protocol without creating a thread,
/// sending a turn, or changing files in the selected workspace.
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
    final page = await probe.request('thread/turns/list', {
      'threadId': threadId,
      'limit': 1,
      'sortDirection': 'desc',
      'itemsView': 'full',
    });
    final turns = page['data'] as Iterable?;
    stdout.writeln(
      'Verified thread $threadId: resumed successfully; '
      'turn page contains ${turns?.length ?? 0} item(s). '
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
          cwd = arguments[++index];
        case '--thread-id':
          threadId = arguments[++index];
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

  void _write(JsonMap message) => _process.stdin.writeln(jsonEncode(message));

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
