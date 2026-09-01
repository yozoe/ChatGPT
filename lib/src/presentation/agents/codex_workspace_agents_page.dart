import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_subagent_avatar.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// A focused Codex-style directory of the current task's subagents.
class AgentsPage extends StatelessWidget {
  const AgentsPage({
    super.key,
    required this.controller,
    required this.onOpenSubagent,
  });

  final CodexController controller;
  final void Function({
    required String threadId,
    required String title,
    required String status,
    required String prompt,
  })
  onOpenSubagent;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final agents = _agentRows();
    final working = agents.where((agent) => agent.status == 'working').toList();
    final completed = agents
        .where((agent) => agent.status != 'working')
        .toList();
    return Column(
      children: [
        const SizedBox(
          height: 56,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '智能体',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: palette.border),
        Expanded(
          child: ListView(
            key: const Key('agents-page'),
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
            children: [
              _section(
                context,
                label: '已开启 · ${working.length}',
                rows: working,
                emptyLabel: '没有已开启的子智能体',
              ),
              const SizedBox(height: 32),
              _section(
                context,
                label: '完成 · ${completed.length}',
                rows: completed,
                emptyLabel: '尚未完成子智能体任务',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 合并已持久化活动与当前实时活动，并按最近创建时间排序。
  /// Merges persisted and live activities, then sorts them by creation time.
  List<
    ({
      String threadId,
      String title,
      String status,
      String prompt,
      bool external,
      DateTime createdAt,
    })
  >
  _agentRows() {
    final entries = controller.entries
        .where(
          (entry) =>
              entry.activityKind == 'collaboration' &&
              entry.linkedThreadId != null,
        )
        .toList(growable: false);
    final rows = entries
        .map(
          (entry) => (
            threadId: entry.linkedThreadId!,
            title: entry.title,
            status: entry.activityStatus ?? 'working',
            prompt: entry.activityPrompt ?? '',
            external: entry.linkedThreadId!.startsWith('external-bridge-'),
            createdAt: entry.createdAt,
          ),
        )
        .toList(growable: true);
    for (final active in controller.activeCollaborationActivities) {
      final activeThreadId = active.linkedThreadId;
      if (activeThreadId == null ||
          rows.any((row) => row.threadId == activeThreadId)) {
        continue;
      }
      rows.add((
        threadId: activeThreadId,
        title: active.label,
        status: active.status ?? 'working',
        prompt: active.prompt,
        external: active.isExternalBridge,
        createdAt: DateTime.now(),
      ));
    }
    rows.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return rows;
  }

  Widget _section(
    BuildContext context, {
    required String label,
    required List<
      ({
        String threadId,
        String title,
        String status,
        String prompt,
        bool external,
        DateTime createdAt,
      })
    >
    rows,
    required String emptyLabel,
  }) {
    final palette = YeknomPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(emptyLabel, style: TextStyle(color: palette.muted)),
            )
          else
            for (final agent in rows) _agentRow(context, agent: agent),
        ],
      ),
    );
  }

  Widget _agentRow(
    BuildContext context, {
    required ({
      String threadId,
      String title,
      String status,
      String prompt,
      bool external,
      DateTime createdAt,
    })
    agent,
  }) {
    final palette = YeknomPalette.of(context);
    return InkWell(
      key: Key('agents-open-${agent.threadId}'),
      onTap: agent.external
          ? null
          : () => onOpenSubagent(
              threadId: agent.threadId,
              title: agent.title,
              status: agent.status,
              prompt: agent.prompt,
            ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SubagentAvatar(agentId: agent.threadId, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                agent.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.trace),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              _relativeTime(agent.createdAt),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime value) {
    final elapsed = DateTime.now().difference(value);
    if (elapsed.inMinutes < 1) return '刚刚';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
    if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
    return '${elapsed.inDays} 天前';
  }
}
