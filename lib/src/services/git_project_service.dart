import 'dart:io';

import '../domain/git_project_status.dart';

/// 通过只读 `git` 命令读取当前项目状态和 Diff；永不执行会修改仓库的 Git 子命令。
/// Reads project status and diffs through read-only `git` commands; it never invokes Git subcommands that modify a repository.
class GitProjectService {
  static const _maximumDiffCharacters = 120000;

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
  }) async {
    try {
      if (change.isUntracked) {
        final result = await _run(workspace, [
          'diff',
          '--no-index',
          '--no-ext-diff',
          '--no-color',
          '--',
          '/dev/null',
          change.path,
        ]);
        if (result.exitCode > 1) throw StateError(_errorOf(result));
        return _limitDiff(result.stdout);
      }
      final results = await Future.wait([
        _run(workspace, [
          'diff',
          '--cached',
          '--no-ext-diff',
          '--no-color',
          '--',
          change.path,
        ]),
        _run(workspace, [
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
          _errorOf(results.firstWhere((result) => result.exitCode != 0)),
        );
      }
      return _limitDiff(output);
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

  /// 限制超大 Diff 的字符数，避免诊断窗口占用过多内存。
  /// Limits oversized diffs to avoid excessive diagnostics-window memory use.
  String _limitDiff(String value) => value.length <= _maximumDiffCharacters
      ? value
      : '${value.substring(0, _maximumDiffCharacters)}\n\n… Diff 已截断，仅显示前 $_maximumDiffCharacters 个字符。';
}
