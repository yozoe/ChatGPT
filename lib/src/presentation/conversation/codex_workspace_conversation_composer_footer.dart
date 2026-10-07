import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/domain/local_worktree_record.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_context_usage_button.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_model_controls.dart';

class ComposerPanelFooter extends StatelessWidget {
  const ComposerPanelFooter({
    super.key,
    required this.controller,
    required this.goalMode,
    required this.managedWorktrees,
    required this.useManagedWorktree,
    required this.contextUsage,
    required this.buildAddMenu,
    required this.onAddAction,
    required this.onLeaveGoalMode,
    required this.onSelectWorktree,
    required this.onSubmit,
  });

  final CodexController controller;
  final bool goalMode;
  final List<LocalWorktreeRecord> managedWorktrees;
  final bool useManagedWorktree;
  final ({int used, int maximum})? contextUsage;
  final List<PopupMenuEntry<AddMenuAction>> Function(BuildContext) buildAddMenu;
  final Future<void> Function(AddMenuAction) onAddAction;
  final VoidCallback onLeaveGoalMode;
  final Future<void> Function(String) onSelectWorktree;
  final Future<bool> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showAttachment = constraints.maxWidth >= 420;
        final showApproval = constraints.maxWidth >= 340;
        final showApprovalLabel =
            constraints.maxWidth >= (goalMode ? 520 : 460);
        final showGoalMode = goalMode && constraints.maxWidth >= 400;
        final showModel = constraints.maxWidth >= 240;
        final showWorktree = constraints.maxWidth >= 520;
        return Row(
          children: [
            if (showAttachment)
              PopupMenuButton<AddMenuAction>(
                key: const Key('composer-add-button'),
                enabled: controller.canSend || controller.canQueueTurnSteer,
                tooltip: '添加上下文',
                icon: const Icon(Icons.add, size: 20),
                constraints: const BoxConstraints(
                  minWidth: 390,
                  maxWidth: 470,
                  maxHeight: 620,
                ),
                color: palette.field,
                surfaceTintColor: Colors.transparent,
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: palette.controlBorder),
                ),
                menuPadding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                onOpened: () {
                  if (controller.skills.isEmpty && !controller.skillsLoading) {
                    unawaited(controller.refreshSkills());
                  }
                },
                onSelected: (action) => unawaited(onAddAction(action)),
                itemBuilder: buildAddMenu,
              ),
            if (showApproval)
              PopupMenuButton<ApprovalMode>(
                tooltip: '审批模式：${controller.approvalMode.label}',
                onSelected: controller.setApprovalMode,
                itemBuilder: (context) => ApprovalMode.values
                    .map(
                      (mode) => CheckedPopupMenuItem(
                        value: mode,
                        checked: controller.approvalMode == mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(growable: false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 16),
                      if (showApprovalLabel) ...[
                        const SizedBox(width: 5),
                        Text(
                          controller.approvalMode.label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (showGoalMode) ...[
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: palette.controlBorder,
              ),
              Semantics(
                button: true,
                label: '目标，点击退出目标输入',
                child: InkWell(
                  key: const Key('composer-goal-mode-control'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: onLeaveGoalMode,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.track_changes_outlined,
                          size: 16,
                          color: palette.muted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '目标',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (showWorktree &&
                controller.activeThreadId == null &&
                controller.workspacePath != null &&
                controller.gitProjectStatus?.isRepository == true) ...[
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                key: const Key('composer-worktree-toggle'),
                onSelected: (value) => unawaited(onSelectWorktree(value)),
                itemBuilder: (context) => [
                  CheckedPopupMenuItem<String>(
                    value: 'local',
                    checked: !useManagedWorktree,
                    child: const Text('本地'),
                  ),
                  PopupMenuItem<String>(
                    value:
                        'new:${controller.gitProjectStatus?.branch ?? 'HEAD'}',
                    child: Text(
                      '新建工作树 · ${controller.gitProjectStatus?.branch ?? '当前提交'}',
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'choose-base',
                    child: Text('从其他分支新建…'),
                  ),
                  ...managedWorktrees.map(
                    (record) => PopupMenuItem<String>(
                      value: record.worktreeId,
                      child: Text(record.worktreeId),
                    ),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      size: 15,
                      color: useManagedWorktree
                          ? palette.active
                          : palette.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      useManagedWorktree ? '工作树' : '本地',
                      style: TextStyle(
                        color: useManagedWorktree
                            ? palette.active
                            : palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            if (showModel) ...[
              ComposerContextUsageButton(
                usedTokens: contextUsage?.used,
                maximumTokens: contextUsage?.maximum,
              ),
              const SizedBox(width: 6),
              ComposerModelControls(
                controller: controller,
                compact: constraints.maxWidth < 430,
              ),
              const SizedBox(width: 8),
            ],
            if (controller.canStop)
              IconButton.filled(
                tooltip: '停止当前任务',
                onPressed: controller.stopCurrentTurn,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  fixedSize: const Size.square(36),
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                icon: const Icon(Icons.stop, size: 19),
              )
            else
              IconButton.filled(
                tooltip: '发送任务',
                onPressed: controller.canSend ? onSubmit : null,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  fixedSize: const Size.square(36),
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
          ],
        );
      },
    );
  }
}
