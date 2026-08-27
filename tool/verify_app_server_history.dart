import 'dart:async';
import 'dart:io';
import 'verify_app_server_history_helpers.dart';

typedef _Options = Options;
typedef _AppServerProbe = AppServerProbe;

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
