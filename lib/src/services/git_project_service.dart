import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/git_project_status.dart';

/// 通过只读 `git` 命令读取当前项目状态和 Diff；永不执行会修改仓库的 Git 子命令。
/// Reads project status and diffs through read-only `git` commands; it never invokes Git subcommands that modify a repository.
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
