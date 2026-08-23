import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/git_project_status.dart';

/// 读取项目 Git 状态和 Diff，并仅在用户明确操作时执行受限的 Git 写入命令。
/// Reads project Git state and diffs, running restricted Git writes only after an explicit user action.
class GitProjectService {
  static const maximumDiffCharacters = 120000;
  static const truncatedDiffMarker =
      '… Diff 已截断，仅显示前 $maximumDiffCharacters 个字符。';

  /// 检查指定项目是否为 Git 仓库，并读取当前分支和未提交文件状态。
  /// Checks whether a workspace is a Git repository and reads its current branch and uncommitted file statuses.
  Future<GitProjectStatus> inspect(String workspace) async {
    try {
      final repository = await _run(workspace, const [
        'rev-parse',
        '--is-inside-work-tree',
      ]);
      if (repository.exitCode != 0 || repository.stdout.trim() != 'true') {
        return const GitProjectStatus(isRepository: false);
      }
      final results = await Future.wait([
        _run(workspace, const ['branch', '--show-current']),
        _run(workspace, const [
          'status',
          '--porcelain=v1',
          '--untracked-files=all',
          '-z',
        ]),
      ]);
      final branchResult = results[0];
      final statusResult = results[1];
      if (branchResult.exitCode != 0 || statusResult.exitCode != 0) {
        return GitProjectStatus(
          isRepository: true,
          error: _errorOf(
            branchResult.exitCode != 0 ? branchResult : statusResult,
          ),
        );
      }
      return GitProjectStatus(
        isRepository: true,
        branch: branchResult.stdout.trim().isEmpty
            ? 'DETACHED'
            : branchResult.stdout.trim(),
        changes: _parseChanges(statusResult.stdout),
      );
    } catch (error) {
      return GitProjectStatus(isRepository: false, error: _displayError(error));
    }
  }

  /// 读取指定改动的只读 Git Diff；未跟踪文件会以 `/dev/null` 为基准生成预览。
  /// Reads a read-only Git diff for a change; untracked files are previewed against `/dev/null`.
  Future<String> readDiff({
    required String workspace,
    required GitProjectChange change,
  }) async =>
      (await readDiffPreview(workspace: workspace, change: change)).content;

  /// 将指定文件加入暂存区；调用者须在界面中明确触发此操作。
  /// Stages one file after the caller has obtained explicit UI intent.
  Future<void> stageFile({
    required String workspace,
    required GitProjectChange change,
  }) => _runWrite(workspace, ['add', '--', change.path]);

  /// 还原指定文件的暂存区和工作区内容；调用者须先完成不可逆操作确认。
  /// Restores one file's index and working-tree content after destructive-action confirmation.
  Future<void> revertFile({
    required String workspace,
    required GitProjectChange change,
  }) {
    if (change.isUntracked) {
      return _runWrite(workspace, ['clean', '-f', '--', change.path]);
    }
    return _runWrite(workspace, [
      'restore',
      '--source=HEAD',
      '--staged',
      '--worktree',
      '--',
      change.path,
    ]);
  }

  /// 以用户提供的消息创建提交；不会自动暂存任何文件。
  /// Creates a commit with the user-provided message without staging files automatically.
  Future<void> commit({required String workspace, required String message}) =>
      _runWrite(workspace, ['commit', '-m', message]);

  /// 推送当前分支所配置的上游；不会使用 force push。
  /// Pushes the current branch to its configured upstream without force pushing.
  Future<void> push({required String workspace}) =>
      _runWrite(workspace, const ['push']);

  /// 通过已登录的 GitHub CLI 为当前分支创建拉取请求。
  /// Creates a pull request for the current branch through an authenticated GitHub CLI.
  Future<void> createPullRequest({
    required String workspace,
    required String title,
  }) async {
    final result = await _runWriteProcess('gh', [
      'pr',
      'create',
      '--title',
      title,
      '--fill',
    ], workspace);
    if (result.exitCode != 0) throw StateError(_errorOf(result));
  }

  /// 读取 Diff 及截断状态，供界面明确提示大文件预览限制。
  /// Reads a diff with truncation metadata so the UI can explain large-preview limits.
  Future<GitDiffPreview> readDiffPreview({
    required String workspace,
    required GitProjectChange change,
  }) async {
    try {
      if (change.isUntracked) {
        final result = await _runDiff(workspace, [
          'diff',
          '--no-index',
          '--no-ext-diff',
          '--no-color',
          '--',
          '/dev/null',
          change.path,
        ]);
        if (result.exitCode > 1 && !result.truncated) {
          throw StateError(_diffErrorOf(result));
        }
        return _limitDiff(result.stdout, truncated: result.truncated);
      }
      final results = await Future.wait([
        _runDiff(workspace, [
          'diff',
          '--cached',
          '--no-ext-diff',
          '--no-color',
          '--',
          change.path,
        ]),
        _runDiff(workspace, [
          'diff',
          '--no-ext-diff',
          '--no-color',
          '--',
          change.path,
        ]),
      ]);
      final output = [
        if (results[0].stdout.trim().isNotEmpty) results[0].stdout,
        if (results[1].stdout.trim().isNotEmpty) results[1].stdout,
      ].join('\n');
      if (results.any((result) => result.exitCode != 0) && output.isEmpty) {
        throw StateError(
          _diffErrorOf(results.firstWhere((result) => result.exitCode != 0)),
        );
      }
      return _limitDiff(
        output,
        truncated: results.any((result) => result.truncated),
      );
    } catch (error) {
      throw StateError(_displayError(error));
    }
  }

  /// 运行不带 Shell 的 Git 只读命令，并限制单次等待时间。
  /// Runs a non-shell read-only Git command with a bounded wait time.
  Future<ProcessResult> _run(String workspace, List<String> arguments) {
    return Process.run(
      'git',
      arguments,
      workingDirectory: workspace,
      runInShell: false,
    ).timeout(const Duration(seconds: 8));
  }

  /// 执行单个受限 Git 写入并将 Git stderr 转换为界面错误。
  /// Runs one restricted Git write and converts Git stderr into a UI error.
  Future<void> _runWrite(String workspace, List<String> arguments) async {
    final result = await _runWriteProcess('git', arguments, workspace);
    if (result.exitCode != 0) throw StateError(_errorOf(result));
  }

  /// 运行可变更本地仓库或远端的命令；超时时终止进程，避免界面误报失败后操作仍继续。
  /// Runs a repository-mutating command and kills it on timeout so it cannot continue after the UI reports failure.
  Future<ProcessResult> _runWriteProcess(
    String executable,
    List<String> arguments,
    String workspace,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workspace,
      runInShell: false,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 60),
      );
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } on TimeoutException {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // The operating system may need more time to reap a network command.
      }
      throw TimeoutException('Git 写入操作超时，已请求终止。');
    }
  }

  /// 流式读取 Git Diff，在达到预览上限时终止子进程，避免缓冲完整输出。
  /// Streams Git diff output and stops the subprocess at the preview limit.
  Future<_GitDiffCommandResult> _runDiff(
    String workspace,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      'git',
      arguments,
      workingDirectory: workspace,
      runInShell: false,
    );
    final stdoutFuture = _collectLimitedText(
      process.stdout,
      maximumCharacters: maximumDiffCharacters,
      onLimit: process.kill,
    );
    final stderrFuture = _collectLimitedText(
      process.stderr,
      maximumCharacters: 16000,
    );
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        process.kill();
        throw TimeoutException('Git Diff 读取超时。');
      },
    );
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    return _GitDiffCommandResult(
      exitCode: exitCode,
      stdout: stdout.content,
      stderr: stderr.content,
      truncated: stdout.truncated,
    );
  }

  /// 解码并限制进程文本流；达到限制后继续丢弃剩余内容或调用终止回调。
  /// Decodes and bounds a process text stream, optionally stopping its producer.
  Future<_LimitedText> _collectLimitedText(
    Stream<List<int>> source, {
    required int maximumCharacters,
    bool Function()? onLimit,
  }) async {
    final buffer = StringBuffer();
    var truncated = false;
    await for (final chunk in source.transform(
      const Utf8Decoder(allowMalformed: true),
    )) {
      if (truncated) continue;
      final remaining = maximumCharacters - buffer.length;
      if (chunk.length <= remaining) {
        buffer.write(chunk);
        continue;
      }
      if (remaining > 0) buffer.write(chunk.substring(0, remaining));
      truncated = true;
      onLimit?.call();
    }
    return _LimitedText(content: buffer.toString(), truncated: truncated);
  }

  /// 解析 `git status --porcelain=v1 -z` 的 NUL 分隔记录，包括重命名和复制条目。
  /// Parses NUL-delimited `git status --porcelain=v1 -z` records, including rename and copy entries.
  List<GitProjectChange> _parseChanges(String raw) {
    final records = raw.split('\u0000');
    final changes = <GitProjectChange>[];
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      if (record.length < 4) continue;
      final code = record.substring(0, 2);
      final path = record.substring(3);
      final renamedOrCopied = code.contains('R') || code.contains('C');
      final previousPath = renamedOrCopied && index + 1 < records.length
          ? records[++index]
          : null;
      changes.add(
        GitProjectChange(code: code, path: path, previousPath: previousPath),
      );
    }
    return changes;
  }

  /// 将异常或 Git 错误转换为适合界面展示的简短文本。
  /// Converts an exception or Git error into short displayable text.
  String _displayError(Object error) =>
      error.toString().replaceFirst('Bad state: ', '');

  /// 优先返回 Git stderr，其次返回退出码说明。
  /// Returns Git stderr when available, otherwise an exit-code description.
  String _errorOf(ProcessResult result) {
    final error = result.stderr.toString().trim();
    return error.isEmpty ? 'Git 命令失败（退出码 ${result.exitCode}）。' : error;
  }

  /// 返回流式 Diff 命令的 stderr，缺失时使用退出码。
  /// Returns stderr from a streamed diff command, falling back to its exit code.
  String _diffErrorOf(_GitDiffCommandResult result) {
    final error = result.stderr.trim();
    return error.isEmpty ? 'Git 命令失败（退出码 ${result.exitCode}）。' : error;
  }

  /// 生成带有明确截断元数据和提示文本的有界 Diff 预览。
  /// Builds a bounded diff preview with explicit truncation metadata and text.
  GitDiffPreview _limitDiff(String value, {bool truncated = false}) {
    final wasTruncated = truncated || value.length > maximumDiffCharacters;
    final content = value.length <= maximumDiffCharacters
        ? value
        : value.substring(0, maximumDiffCharacters);
    return GitDiffPreview(
      content: wasTruncated ? '$content\n\n$truncatedDiffMarker' : content,
      truncated: wasTruncated,
    );
  }
}

class _LimitedText {
  const _LimitedText({required this.content, required this.truncated});

  final String content;
  final bool truncated;
}

class _GitDiffCommandResult {
  const _GitDiffCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.truncated,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool truncated;
}
