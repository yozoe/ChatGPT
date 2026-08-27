// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_git_project_dialog.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_git_diff_viewer.dart';

class GitProjectDialogState extends State<GitProjectDialog> {
  final TextEditingController _search = TextEditingController();
  GitChangeFilter _filter = GitChangeFilter.all;

  /// 收集提交消息并由用户显式选择仅提交或提交后推送。
  /// Collects a commit message and lets the user explicitly choose commit or commit-and-push.
  Future<void> _commitOrPush() async {
    final message = TextEditingController();
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提交或推送'),
        content: TextField(
          controller: message,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(labelText: '提交消息'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('仅提交'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('提交并推送'),
          ),
        ],
      ),
    );
    final text = message.text.trim();
    message.dispose();
    if (action == null || text.isEmpty) return;
    final committed = await widget.controller.commitGitChanges(text);
    if (committed && action) await widget.controller.pushGitBranch();
  }

  /// 收集 PR 标题并通过本机已认证的 GitHub CLI 创建拉取请求。
  /// Collects a PR title and creates it through the locally authenticated GitHub CLI.
  Future<void> _createPullRequest() async {
    final title = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建拉取请求'),
        content: TextField(
          controller: title,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(labelText: '拉取请求标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final text = title.text.trim();
    title.dispose();
    if (confirmed == true && text.isNotEmpty) {
      await widget.controller.createGitPullRequest(text);
    }
  }

  /// 二次确认后丢弃指定文件的 Git 改动，避免点击行尾按钮即丢失内容。
  /// Discards a file's Git changes only after a second confirmation.
  Future<void> _revertChange(GitProjectChange change) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('还原文件改动？'),
        content: Text('“${change.path}”的暂存区和工作区改动将被丢弃，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('还原'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.revertGitChange(change);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 构建筛选控件、文件级 Git 操作和当前 Diff 预览。
  /// Builds filters, file-level Git actions, and the current Diff preview.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final status = controller.gitProjectStatus;
    final palette = YeknomPalette.of(context);
    final counts = status?.changeCounts;
    final changes =
        status?.filteredChanges(filter: _filter, query: _search.text) ??
        const <GitProjectChange>[];
    return AlertDialog(
      key: const Key('git-project-dialog'),
      title: const Text('Git 项目'),
      content: SizedBox(
        width: 920,
        height: 590,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择文件可查看 Diff、暂存或还原；提交、推送和创建 PR 均需显式确认。'),
            const SizedBox(height: 12),
            if (controller.gitOperationError case final error?) ...[
              Text(error, style: TextStyle(color: palette.fault)),
              const SizedBox(height: 8),
            ],
            if (controller.gitProjectLoading)
              const LinearProgressIndicator()
            else if (controller.gitProjectError case final error?)
              Text(error, style: TextStyle(color: palette.fault))
            else if (status == null || !status.isRepository)
              const Expanded(child: Center(child: Text('当前项目不是 Git 仓库。')))
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('分支：${status.branch ?? 'DETACHED'}')),
                  Chip(label: Text('暂存：${counts!.staged}')),
                  Chip(label: Text('未暂存：${counts.unstaged}')),
                  Chip(label: Text('未跟踪：${counts.untracked}')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('git-change-search'),
                      controller: _search,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 19),
                        hintText: '搜索文件路径',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<GitChangeFilter>(
                    key: const Key('git-change-filter'),
                    value: _filter,
                    onChanged: (value) {
                      if (value != null) setState(() => _filter = value);
                    },
                    items: GitChangeFilter.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 320,
                      child: status.changes.isEmpty
                          ? const Center(child: Text('工作区没有未提交改动。'))
                          : changes.isEmpty
                          ? const Center(child: Text('没有符合筛选条件的文件。'))
                          : ListView.separated(
                              key: const Key('git-change-list'),
                              itemCount: changes.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final change = changes[index];
                                final selected =
                                    controller.gitDiffChange == change;
                                return ListTile(
                                  selected: selected,
                                  selectedTileColor: palette.selected,
                                  dense: true,
                                  leading: Icon(
                                    change.isUntracked
                                        ? Icons.note_add_outlined
                                        : Icons.description_outlined,
                                    size: 18,
                                  ),
                                  title: Text(
                                    change.path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    change.previousPath == null
                                        ? '${change.label} · ${change.code}'
                                        : '${change.label}：${change.previousPath} → ${change.path}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!change.isStaged)
                                        IconButton(
                                          tooltip: '暂存文件',
                                          onPressed:
                                              controller.gitOperationRunning
                                              ? null
                                              : () => controller.stageGitChange(
                                                  change,
                                                ),
                                          icon: const Icon(
                                            Icons.add_box_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: '还原文件改动',
                                        onPressed:
                                            controller.gitOperationRunning
                                            ? null
                                            : () => _revertChange(change),
                                        icon: const Icon(
                                          Icons.restore_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => controller.showGitDiff(change),
                                );
                              },
                            ),
                    ),
                    const VerticalDivider(width: 24),
                    Expanded(
                      child: GitDiffViewer(
                        change: controller.gitDiffChange,
                        diff: controller.gitDiff,
                        loading: controller.gitDiffLoading,
                        truncated: controller.gitDiffTruncated,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: controller.gitOperationRunning ? null : _commitOrPush,
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: const Text('提交或推送'),
        ),
        TextButton.icon(
          onPressed: controller.gitOperationRunning ? null : _createPullRequest,
          icon: const Icon(Icons.call_merge_outlined, size: 18),
          label: const Text('创建拉取请求'),
        ),
        TextButton.icon(
          onPressed: controller.gitProjectLoading
              ? null
              : controller.refreshGitProject,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('刷新'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
