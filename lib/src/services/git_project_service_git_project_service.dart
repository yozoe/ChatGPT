// Extracted class from git_project_service.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'git_project_service_support.dart';
import 'git_project_service_limited_text.dart';
import 'git_project_service_git_diff_command_result.dart';

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

  /// Lists local and remote branches that can be used as a review baseline.
  Future<List<String>> listReviewBaseBranches(String workspace) async {
    final repository = await _run(workspace, const [
      'rev-parse',
      '--is-inside-work-tree',
    ]);
    if (repository.exitCode != 0 || repository.stdout.trim() != 'true') {
      return const [];
    }
    final result = await _run(workspace, const [
      'for-each-ref',
      '--format=%(refname:short)',
      'refs/remotes',
      'refs/heads',
    ]);
    if (result.exitCode != 0) throw StateError(_errorOf(result));
    final output = result.stdout is String ? result.stdout as String : '';
    final branches =
        output
            .split('\n')
            .map((branch) => branch.trim())
            .where((branch) => branch.isNotEmpty && !branch.endsWith('/HEAD'))
            .toSet()
            .toList(growable: false)
          ..sort();
    return branches;
  }

  /// 列出可供当前工作区检出的本地分支。
  /// Lists local branches that can be checked out in the current workspace.
  Future<List<String>> listLocalBranches(String workspace) async {
    final result = await _run(workspace, const [
      'branch',
      '--format=%(refname:short)',
    ]);
    if (result.exitCode != 0) throw StateError(_errorOf(result));
    final output = result.stdout is String ? result.stdout as String : '';
    return output
        .split('\n')
        .map((branch) => branch.trim())
        .where((branch) => branch.isNotEmpty)
        .toList(growable: false);
  }

  /// 检出已有本地分支；未提交改动冲突时由 Git 拒绝操作。
  /// Checks out an existing local branch, allowing Git to reject conflicting changes.
  Future<void> checkoutBranch({
    required String workspace,
    required String branch,
  }) => _runWrite(workspace, ['switch', '--', branch]);

  /// 校验名称并创建、检出新的本地分支。
  /// Validates, creates, and checks out a new local branch.
  Future<void> createAndCheckoutBranch({
    required String workspace,
    required String branch,
  }) async {
    final name = branch.trim();
    if (name.isEmpty) throw StateError('请输入分支名称。');
    final validation = await _run(workspace, [
      'check-ref-format',
      '--branch',
      name,
    ]);
    if (validation.exitCode != 0) throw StateError('分支名称无效：$name');
    await _runWrite(workspace, ['switch', '-c', name]);
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

  /// 反向应用任务级统一 Diff；先执行完整检查，避免文件后续变化时产生部分撤销。
  /// Reverse-applies a turn-level unified diff after a full dry-run check so later edits cannot cause a partial undo.
  Future<void> reverseApplyDiff({
    required String workspace,
    required String diff,
    required Iterable<String> expectedPaths,
  }) async {
    final patch = diff;
    if (patch.trim().isEmpty) throw StateError('没有可撤销的任务 Diff。');
    if (patch.contains(truncatedDiffMarker)) {
      throw StateError('任务 Diff 已截断，无法安全撤销。');
    }
    final normalizedExpectedPaths = <String>{};
    for (final path in expectedPaths) {
      final normalized = _workspaceRelativePath(workspace, path);
      if (normalized == null) {
        throw StateError('文件变更路径不在当前项目内，无法安全撤销：$path');
      }
      normalizedExpectedPaths.add(normalized);
    }
    if (normalizedExpectedPaths.isEmpty) {
      throw StateError('没有可核对的文件变更路径。');
    }
    final patchPaths = await _readPatchPaths(workspace, patch);
    if (patchPaths.length != normalizedExpectedPaths.length ||
        !patchPaths.containsAll(normalizedExpectedPaths)) {
      throw StateError('任务 Diff 与摘要中的文件列表不一致，无法安全撤销。');
    }
    await _rejectStagedPatchPaths(workspace, normalizedExpectedPaths);
    const arguments = [
      'apply',
      '--reverse',
      '--whitespace=nowarn',
      '--recount',
      '-',
    ];
    final check = await _runWriteProcessWithInput(
      'git',
      [...arguments.take(arguments.length - 1), '--check', '-'],
      workspace,
      patch,
    );
    if (check.exitCode != 0) {
      throw StateError('文件已发生变化，无法安全撤销：${_errorOf(check)}');
    }
    final result = await _runWriteProcessWithInput(
      'git',
      arguments,
      workspace,
      patch,
    );
    if (result.exitCode != 0) {
      throw StateError('撤销文件改动失败：${_errorOf(result)}');
    }
  }

  /// 让 Git 解析补丁路径，避免自行处理引号、空格、重命名和转义规则。
  /// Lets Git parse patch paths so quoting, spaces, renames, and escapes follow Git's own rules.
  Future<Set<String>> _readPatchPaths(String workspace, String patch) async {
    final result = await _runWriteProcessWithInput(
      'git',
      const ['apply', '--numstat', '-z', '-'],
      workspace,
      patch,
    );
    if (result.exitCode != 0) {
      throw StateError('任务 Diff 格式无效：${_errorOf(result)}');
    }
    final paths = _parseNullTerminatedNumstat(result.stdout.toString());
    if (paths.isEmpty) throw StateError('任务 Diff 没有可撤销的文件。');
    return paths;
  }

  /// 若目标文件有暂存改动则拒绝撤销，避免仅恢复工作树而把旧改动留在 index。
  /// Rejects staged target paths so undo cannot restore only the worktree while leaving changes in the index.
  Future<void> _rejectStagedPatchPaths(
    String workspace,
    Set<String> paths,
  ) async {
    final repository = await _run(workspace, const [
      'rev-parse',
      '--is-inside-work-tree',
    ]);
    if (repository.exitCode != 0 || repository.stdout.trim() != 'true') return;
    final staged = await _run(workspace, [
      'diff',
      '--cached',
      '--name-only',
      '-z',
      '--',
      ...paths,
    ]);
    if (staged.exitCode != 0) throw StateError(_errorOf(staged));
    final stagedPaths = staged.stdout
        .toString()
        .split('\u0000')
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (stagedPaths.isNotEmpty) {
      throw StateError('以下文件包含暂存改动，请先处理暂存区后再撤销：${stagedPaths.join('、')}');
    }
  }

  /// 解析 `git apply --numstat -z`，普通路径和重命名前后路径均以 NUL 分隔。
  /// Parses `git apply --numstat -z`, including NUL-delimited pre/post paths for renames.
  Set<String> _parseNullTerminatedNumstat(String raw) {
    final paths = <String>{};
    var cursor = 0;
    while (cursor < raw.length) {
      final additionsEnd = raw.indexOf('\t', cursor);
      if (additionsEnd < 0) break;
      final deletionsEnd = raw.indexOf('\t', additionsEnd + 1);
      if (deletionsEnd < 0) break;
      cursor = deletionsEnd + 1;
      if (cursor < raw.length && raw.codeUnitAt(cursor) == 0) {
        cursor++;
        final previousEnd = raw.indexOf('\u0000', cursor);
        if (previousEnd < 0) break;
        final previous = raw.substring(cursor, previousEnd);
        if (previous.isNotEmpty) paths.add(previous);
        cursor = previousEnd + 1;
        final nextEnd = raw.indexOf('\u0000', cursor);
        if (nextEnd < 0) break;
        final next = raw.substring(cursor, nextEnd);
        if (next.isNotEmpty) paths.add(next);
        cursor = nextEnd + 1;
        continue;
      }
      final pathEnd = raw.indexOf('\u0000', cursor);
      if (pathEnd < 0) break;
      final path = raw.substring(cursor, pathEnd);
      if (path.isNotEmpty) paths.add(path);
      cursor = pathEnd + 1;
    }
    return paths;
  }

  /// 将 App Server 路径规范化为项目内相对路径；拒绝绝对越界和 `..`。
  /// Normalizes an App Server path to a workspace-relative path, rejecting absolute escapes and `..`.
  String? _workspaceRelativePath(String workspace, String value) {
    var path = value;
    if (path.trim().isEmpty || path.contains('\u0000')) return null;
    final root = workspace.replaceFirst(RegExp(r'/+$'), '');
    if (path == root) return null;
    if (path.startsWith('$root/')) {
      path = path.substring(root.length + 1);
    } else if (path.startsWith('/')) {
      return null;
    }
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') return null;
      segments.add(segment);
    }
    return segments.isEmpty ? null : segments.join('/');
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
  Future<ProcessResult> _run(String workspace, List<String> arguments) async {
    final process = await Process.start(
      'git',
      arguments,
      workingDirectory: workspace,
      runInShell: false,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 8),
      );
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } on TimeoutException {
      await _terminateProcess(process);
      await Future.wait([stdout, stderr]);
      throw TimeoutException('Git 读取操作超时。');
    }
  }

  Future<void> _terminateProcess(Process process) async {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
      return;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
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
      await _terminateProcess(process);
      await Future.wait([stdout, stderr]);
      throw TimeoutException('Git 写入操作超时，已终止。');
    }
  }

  /// 运行接收标准输入的受限写入命令；任务 Diff 直接写入 stdin，不创建临时补丁文件。
  /// Runs a bounded write command with stdin so a turn diff never needs a temporary patch file.
  Future<ProcessResult> _runWriteProcessWithInput(
    String executable,
    List<String> arguments,
    String workspace,
    String input,
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
      return await (() async {
        process.stdin.add(utf8.encode(input));
        await process.stdin.close();
        final exitCode = await process.exitCode;
        return ProcessResult(process.pid, exitCode, await stdout, await stderr);
      })().timeout(const Duration(seconds: 60));
    } on TimeoutException {
      await _terminateProcess(process);
      await Future.wait([stdout, stderr]);
      throw TimeoutException('撤销操作超时，已终止。');
    }
  }

  /// 流式读取 Git Diff，在达到预览上限时终止子进程，避免缓冲完整输出。
  /// Streams Git diff output and stops the subprocess at the preview limit.
  Future<GitDiffCommandResult> _runDiff(
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
    return GitDiffCommandResult(
      exitCode: exitCode,
      stdout: stdout.content,
      stderr: stderr.content,
      truncated: stdout.truncated,
    );
  }

  /// 解码并限制进程文本流；达到限制后继续丢弃剩余内容或调用终止回调。
  /// Decodes and bounds a process text stream, optionally stopping its producer.
  Future<LimitedText> _collectLimitedText(
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
    return LimitedText(content: buffer.toString(), truncated: truncated);
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
  String _diffErrorOf(GitDiffCommandResult result) {
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
