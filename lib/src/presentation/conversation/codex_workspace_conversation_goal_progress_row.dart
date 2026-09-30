import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

enum GoalProgressAction { edit, clear }

/// Codex-style progress controls for the selected thread's persisted goal.
class GoalProgressRow extends StatelessWidget {
  const GoalProgressRow({
    super.key,
    required this.controller,
    required this.goal,
  });

  final CodexController controller;
  final CodexThreadGoal goal;

  String _statusLabel(CodexController controller) {
    if (goal.isBudgetExhausted) return '预算已用尽';
    if (goal.isActive &&
        controller.shouldShowPendingUserInput &&
        controller.pendingUserInput?.threadId == goal.threadId) {
      return '等待输入';
    }
    return switch (goal.status) {
      'paused' => '已暂停',
      'complete' || 'completed' => '已完成',
      'blocked' => '需要输入',
      'usageLimited' => '用量已达上限',
      'budgetLimited' => '预算已用尽',
      _ => controller.activeGoalIsProgressing ? '进行中' : '等待继续',
    };
  }

  String get _usageLabel {
    final minutes = goal.timeUsedSeconds ~/ 60;
    final time = minutes > 0 ? '$minutes 分钟' : '${goal.timeUsedSeconds} 秒';
    final budget = goal.tokenBudget;
    if (budget == null || budget <= 0) return '累计 $time';
    return '${goal.tokensUsed} / $budget tokens · 累计 $time';
  }

  String get _elapsedLabel {
    final totalSeconds = goal.timeUsedSeconds.clamp(0, 86400000);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  Future<void> _editGoal(BuildContext context) async {
    var draft = goal.objective;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑目标'),
        content: TextFormField(
          key: const Key('goal-edit-field'),
          initialValue: goal.objective,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          maxLength: 4000,
          decoration: const InputDecoration(hintText: '描述结果、约束和可验证的完成条件'),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) {
            final normalized = value.trim();
            if (normalized.isNotEmpty) {
              Navigator.of(dialogContext).pop(normalized);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('goal-edit-save-button'),
            onPressed: () {
              final normalized = draft.trim();
              if (normalized.isNotEmpty) {
                Navigator.of(dialogContext).pop(normalized);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) {
      await controller.editActiveGoal(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final busy = controller.goalOperationInProgress;
    final progress = goal.progress;
    final error =
        controller.goalOperationError ?? controller.activeGoalContinuationError;
    final waiting = goal.isActive && controller.activeGoalIsWaiting;
    final waitingForUserInput =
        controller.shouldShowPendingUserInput &&
        controller.pendingUserInput?.threadId == goal.threadId;
    if (goal.isActive &&
        controller.activeGoalIsProgressing &&
        !waitingForUserInput &&
        error == null) {
      return _buildRunningGoalBar(context, palette, busy: busy);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        key: const Key('goal-progress-row'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
        decoration: BoxDecoration(
          color: palette.raised,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.track_changes_outlined, size: 17, color: palette.muted),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          goal.objective,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusLabel(controller),
                        key: const Key('goal-progress-status'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              goal.isPaused ||
                                  !controller.activeGoalIsProgressing
                              ? palette.warning
                              : palette.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (error != null)
                    Text(
                      error,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.fault),
                    )
                  else
                    Row(
                      children: [
                        if (progress != null) ...[
                          SizedBox(
                            width: 70,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 2,
                              color: palette.active,
                              backgroundColor: palette.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            _usageLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.faint, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(9),
                child: SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (!goal.isTerminal || goal.isBlocked)
              IconButton(
                key: const Key('goal-pause-resume-button'),
                tooltip: waiting
                    ? '继续目标'
                    : goal.canResume
                    ? '恢复目标'
                    : '暂停目标',
                onPressed: waiting
                    ? controller.continueActiveGoal
                    : goal.canResume
                    ? controller.resumeActiveGoal
                    : controller.pauseActiveGoal,
                icon: Icon(
                  goal.isPaused || waiting
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
              ),
            PopupMenuButton<GoalProgressAction>(
              key: const Key('goal-actions-button'),
              tooltip: '目标操作',
              enabled: !busy,
              icon: const Icon(Icons.more_horiz, size: 19),
              onSelected: (action) {
                switch (action) {
                  case GoalProgressAction.edit:
                    unawaited(_editGoal(context));
                  case GoalProgressAction.clear:
                    unawaited(controller.clearActiveGoal());
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: GoalProgressAction.edit,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.edit_outlined, size: 18),
                    title: Text('编辑目标'),
                  ),
                ),
                PopupMenuItem(
                  value: GoalProgressAction.clear,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.close, size: 18),
                    title: Text('清除目标'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunningGoalBar(
    BuildContext context,
    YeknomPalette palette, {
    required bool busy,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    child: Container(
      key: const Key('goal-progress-row-running'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.raised,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.track_changes_outlined, size: 16, color: palette.muted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '进行中的目标：${goal.objective}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _elapsedLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.faint, fontSize: 11),
          ),
          const SizedBox(width: 2),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(7),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              key: const Key('goal-pause-running-button'),
              tooltip: '暂停目标',
              onPressed: controller.pauseActiveGoal,
              icon: const Icon(Icons.pause_rounded, size: 17),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            ),
          PopupMenuButton<GoalProgressAction>(
            key: const Key('goal-running-actions-button'),
            tooltip: '目标操作',
            enabled: !busy,
            icon: const Icon(Icons.more_horiz, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            onSelected: (action) {
              switch (action) {
                case GoalProgressAction.edit:
                  unawaited(_editGoal(context));
                case GoalProgressAction.clear:
                  unawaited(controller.clearActiveGoal());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: GoalProgressAction.edit,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_outlined, size: 18),
                  title: Text('编辑目标'),
                ),
              ),
              PopupMenuItem(
                value: GoalProgressAction.clear,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.close, size: 18),
                  title: Text('清除目标'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
