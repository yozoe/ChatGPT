// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_action_row.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_thread_row.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_subagents_summary.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_branch_menu.dart';

/// 右侧环境检查器，集中呈现审批、文件变更和子智能体摘要。
/// Right-side environment inspector for approvals, file changes, and subagent summaries.
class Inspector extends StatelessWidget {
  const Inspector({
    super.key,
    required this.width,
    required this.controller,
    required this.onShowTaskChanges,
    required this.onShowGitProject,
    required this.onShowAgents,
  });

  final double width;
  final CodexController controller;
  final Future<void> Function() onShowTaskChanges;
  final Future<void> Function() onShowGitProject;
  final VoidCallback onShowAgents;

  Widget _taskProjectChange(
    BuildContext context,
    ({String root, List<CodexFileChange> changes}) group,
    String? turnDiff,
  ) {
    final palette = YeknomPalette.of(context);
    final stats = reliableFileChangeStats(group.changes, turnDiff);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          workspaceRootName(group.root),
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
        InspectorActionRow(
          icon: Icons.add_box_outlined,
          label: '变更',
          trailing: stats == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+${stats.additions}',
                      style: TextStyle(
                        color: palette.ack,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '-${stats.deletions}',
                      style: TextStyle(
                        color: palette.fault,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
          onTap: onShowTaskChanges,
        ),
      ],
    );
  }

  /// 构建采用 Codex 信息卡层级的审批与文件变更检查器。
  /// Builds the approval and file-change inspector with Codex information-card hierarchy.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final branchAnchorKey = GlobalKey();
    final taskChanges = controller.fileChanges;
    final hasTurnDiff = controller.turnDiff?.trim().isNotEmpty ?? false;
    final taskGroups = groupTaskFileChanges(
      primaryRoot: controller.workspacePath,
      additionalRoots: controller.additionalWorkspacePaths,
      changes: taskChanges,
    );
    return SizedBox(
      key: const Key('environment-inspector-pane'),
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Container(
          key: const Key('codex-environment-card'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.module,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.border),
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '环境信息',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: palette.muted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.35,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    if (taskChanges.isNotEmpty || hasTurnDiff)
                      for (final group in taskGroups)
                        _taskProjectChange(context, group, controller.turnDiff),
                    InspectorActionRow(
                      icon: Icons.description_outlined,
                      label: '任务文件',
                      trailing: Text(
                        taskChanges.isNotEmpty
                            ? fileChangeCountLabel(taskChanges.length)
                            : hasTurnDiff
                            ? '完整 Diff'
                            : fileChangeCountLabel(0),
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                      onTap: onShowTaskChanges,
                    ),
                    InspectorActionRow(
                      icon: Icons.laptop_mac_outlined,
                      label: '本地',
                      trailing: Icon(Icons.expand_more, color: palette.muted),
                      onTap: onShowGitProject,
                    ),
                    KeyedSubtree(
                      key: branchAnchorKey,
                      child: InspectorActionRow(
                        icon: Icons.account_tree_outlined,
                        label: controller.gitProjectStatus?.branch ?? '未检测到分支',
                        trailing: Icon(Icons.expand_more, color: palette.muted),
                        onTap: () async {
                          final anchorContext = branchAnchorKey.currentContext;
                          if (anchorContext == null) return;
                          await showInspectorBranchMenu(
                            context,
                            anchorContext: anchorContext,
                            controller: controller,
                          );
                        },
                      ),
                    ),
                    InspectorActionRow(
                      icon: Icons.tune_outlined,
                      label: '提交或推送',
                      onTap: onShowGitProject,
                    ),
                    InspectorActionRow(
                      icon: Icons.call_merge_outlined,
                      label: '创建拉取请求',
                      onTap: onShowGitProject,
                    ),
                    InspectorActionRow(
                      icon: Icons.compare_arrows_outlined,
                      label: '比较分支',
                      trailing: Icon(
                        Icons.north_east,
                        size: 16,
                        color: palette.muted,
                      ),
                      onTap: onShowGitProject,
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: palette.border),
                    const SizedBox(height: 16),
                    InspectorSubagentsSummary(
                      controller: controller,
                      onShowAll: onShowAgents,
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: palette.border),
                    const SizedBox(height: 12),
                    InspectorThreadRow(threadId: controller.activeThreadId),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
