// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_section_header.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_action_row.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_thread_row.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_file_changes_list.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_subagents_summary.dart';

class Inspector extends StatelessWidget {
  const Inspector({
    required this.width,
    required this.controller,
    required this.onShowGitProject,
    required this.onShowAgents,
  });

  final double width;
  final CodexController controller;
  final Future<void> Function() onShowGitProject;
  final VoidCallback onShowAgents;

  /// 构建采用 Codex 信息卡层级的审批与文件变更检查器。
  /// Builds the approval and file-change inspector with Codex information-card hierarchy.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return SizedBox(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '环境信息',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.35,
                    ),
                  ),
                  const SizedBox(height: 22),
                  InspectorActionRow(
                    icon: Icons.add_box_outlined,
                    label: '变更',
                    trailing: Text(
                      fileChangeCountLabel(controller.fileChanges.length),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.active,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: onShowGitProject,
                  ),
                  InspectorActionRow(
                    icon: Icons.laptop_mac_outlined,
                    label: '本地',
                    trailing: Icon(Icons.expand_more, color: palette.muted),
                    onTap: onShowGitProject,
                  ),
                  InspectorActionRow(
                    icon: Icons.account_tree_outlined,
                    label: controller.gitProjectStatus?.branch ?? '未检测到分支',
                    trailing: Icon(Icons.expand_more, color: palette.muted),
                    onTap: onShowGitProject,
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
                  const SizedBox(height: 16),
                  Divider(height: 1, color: palette.border),
                  const SizedBox(height: 16),
                  InspectorSectionHeader(
                    icon: Icons.description_outlined,
                    label: '任务文件',
                    trailing: Text(
                      fileChangeCountLabel(controller.fileChanges.length),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: palette.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: InspectorFileChangesList(
                      changes: controller.fileChanges,
                      turnDiff: controller.turnDiff,
                    ),
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
    );
  }
}
