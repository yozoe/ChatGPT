import 'dart:io';

final _shardPatterns = <String, RegExp>{
  'composer': RegExp(r'(^|/)(composer|goal_plan|plan_mode).*_test\.dart$'),
  'runtime': RegExp(
    r'(^|/)(runtime|approval|mcp_elicitation|failed_turn|network_retry|turn_|completion_reminder|pending_interaction).*_test\.dart$',
  ),
  'browser': RegExp(r'(^|/)(browser|markdown_workspace_preview).*_test\.dart$'),
  'git': RegExp(r'(^|/)(git_|file_change|task_file).*_test\.dart$'),
  'workspace': RegExp(
    r'(^|/)(workspace|sidebar|thread_|timeline_|conversation_|subagent_).*_test\.dart$',
  ),
  'settings': RegExp(
    r'(^|/)(settings|configuration|model_|plugin|session_access|collaboration|history|scheduled|agent_default|theme).*_test\.dart$',
  ),
};

void main(List<String> arguments) {
  final files = _testFiles();
  if (arguments.contains('--verify')) {
    _verifyShards(files);
    return;
  }
  final requested = _argumentValue(arguments, '--shard') ?? 'list';
  if (requested == 'list') {
    stdout.writeln('Available test shards:');
    for (final shard in [..._shardPatterns.keys, 'misc']) {
      final selected = _filesForShard(files, shard);
      stdout.writeln('  $shard (${selected.length} files)');
    }
    return;
  }

  final selected = _filesForShard(files, requested);
  if (selected.isEmpty) {
    stderr.writeln('Unknown or empty test shard: $requested');
    exitCode = 64;
    return;
  }
  stdout.writeln('Running test shard "$requested" (${selected.length} files).');
  final result = Process.runSync('flutter', ['test', ...selected]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
}

void _verifyShards(List<String> files) {
  final violations = <String>[];
  for (final path in files) {
    final matches = _matchingShards(path);
    if (matches.length != 1) {
      violations.add(
        '$path belongs to ${matches.isEmpty ? 'no shard' : matches.join(', ')}',
      );
    }
  }
  if (violations.isNotEmpty) {
    stderr.writeln('Test shard violations:');
    for (final violation in violations) {
      stderr.writeln('  - $violation');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Test shard coverage verified: ${files.length} files, one shard each.',
  );
}

String? _argumentValue(List<String> arguments, String name) {
  final prefix = '$name=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) return argument.substring(prefix.length);
  }
  final index = arguments.indexOf(name);
  if (index >= 0 && index + 1 < arguments.length) return arguments[index + 1];
  return null;
}

List<String> _testFiles() {
  final directory = Directory('test');
  if (!directory.existsSync()) return const [];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceFirst('./', ''))
      .where((path) => path.endsWith('_test.dart'))
      .toList()
    ..sort();
}

List<String> _filesForShard(List<String> files, String shard) {
  if (shard == 'misc') {
    return files
        .where(
          (path) =>
              !_shardPatterns.values.any((pattern) => pattern.hasMatch(path)),
        )
        .toList();
  }
  final pattern = _shardPatterns[shard];
  if (pattern == null) return const [];
  return files.where(pattern.hasMatch).toList();
}

List<String> _matchingShards(String path) {
  final matches = [
    for (final entry in _shardPatterns.entries)
      if (entry.value.hasMatch(path)) entry.key,
  ];
  if (matches.isEmpty) return const ['misc'];
  return matches;
}
