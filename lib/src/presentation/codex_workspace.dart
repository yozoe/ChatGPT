import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../domain/pending_approval.dart';
import '../domain/timeline_entry.dart';

class CodexWorkspace extends StatefulWidget {
  const CodexWorkspace({required this.controller, super.key});

  final CodexController controller;

  @override
  State<CodexWorkspace> createState() => _CodexWorkspaceState();
}

class _CodexWorkspaceState extends State<CodexWorkspace> {
  final TextEditingController _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _chooseWorkspace() async {
    final input = TextEditingController(
      text: widget.controller.workspacePath ?? '',
    );
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择本地项目'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '/Users/you/Code/project',
            labelText: '项目路径',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('使用此目录'),
          ),
        ],
      ),
    );
    input.dispose();
    if (path != null && path.trim().isNotEmpty) {
      await widget.controller.selectWorkspace(path);
    }
  }

  Future<void> _send() async {
    final prompt = _composer.text;
    if (prompt.trim().isEmpty) return;
    _composer.clear();
    await widget.controller.sendPrompt(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  controller: controller,
                  onChooseWorkspace: _chooseWorkspace,
                  onStart: controller.startRuntime,
                  onStop: controller.stopRuntime,
                ),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 980;
                      return Row(
                        children: [
                          _Sidebar(
                            controller: controller,
                            onChooseWorkspace: _chooseWorkspace,
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _ConversationPane(
                              controller: controller,
                              composer: _composer,
                              onSend: _send,
                            ),
                          ),
                          if (!compact) ...[
                            const VerticalDivider(width: 1),
                            _Inspector(controller: controller),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.onChooseWorkspace,
    required this.onStart,
    required this.onStop,
  });

  final CodexController controller;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final color = switch (controller.status) {
      RuntimeStatus.ready => const Color(0xFF68E0B8),
      RuntimeStatus.running => const Color(0xFF82B1FF),
      RuntimeStatus.failed => const Color(0xFFFF8A80),
      _ => const Color(0xFF94A3B8),
    };
    final label = switch (controller.status) {
      RuntimeStatus.stopped => '未启动',
      RuntimeStatus.starting => '连接中',
      RuntimeStatus.ready => '已就绪',
      RuntimeStatus.running => '执行中',
      RuntimeStatus.failed => '已断开',
    };

    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF68E0B8)),
            const SizedBox(width: 10),
            Text('Codex Desk', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 16),
            _StatusPill(label: label, color: color),
            const Spacer(),
            TextButton.icon(
              onPressed: controller.canChooseWorkspace
                  ? onChooseWorkspace
                  : null,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('项目'),
            ),
            const SizedBox(width: 8),
            if (controller.canStopRuntime)
              FilledButton.tonalIcon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止运行时'),
              )
            else
              FilledButton.icon(
                onPressed:
                    controller.workspacePath == null ||
                        controller.status == RuntimeStatus.starting
                    ? null
                    : onStart,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('启动运行时'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller, required this.onChooseWorkspace});

  final CodexController controller;
  final VoidCallback onChooseWorkspace;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('工作区', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            InkWell(
              onTap: controller.canChooseWorkspace ? onChooseWorkspace : null,
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF162131),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A3A50)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.folder_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.workspacePath ?? '选择一个本地项目',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Text('线程', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                IconButton(
                  tooltip: '新建任务',
                  onPressed: controller.canSend
                      ? controller.createThread
                      : null,
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (controller.activeThreadId == null)
              const _MutedText('新任务会在发送第一条消息时创建。')
            else
              _ThreadTile(threadId: controller.activeThreadId!),
            const Spacer(),
            const _MutedText('本地优先 · stdio JSON-RPC'),
          ],
        ),
      ),
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.controller,
    required this.composer,
    required this.onSend,
  });

  final CodexController controller;
  final TextEditingController composer;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '任务控制台',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const _ProviderChip(),
              const SizedBox(width: 8),
              const _ProviderChip(label: 'workspace-write'),
            ],
          ),
        ),
        if (controller.lastError case final error?)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3A1F28),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              error,
              style: const TextStyle(color: Color(0xFFFFB4AB)),
            ),
          ),
        if (controller.pendingApproval case final approval?)
          _ApprovalPanel(
            approval: approval,
            enabled: controller.canRespondToApproval,
            onAccept: () => controller.respondToApproval(accepted: true),
            onDecline: () => controller.respondToApproval(accepted: false),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            itemCount: controller.entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                _TimelineCard(controller.entries[index]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: composer,
                  enabled: controller.canSend,
                  minLines: 2,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '描述你希望 Codex 在这个项目中完成的工作…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (controller.canStop)
                IconButton.filledTonal(
                  tooltip: '停止当前任务',
                  onPressed: controller.stopCurrentTurn,
                  icon: const Icon(Icons.stop_circle_outlined),
                )
              else
                IconButton.filled(
                  tooltip: '发送任务',
                  onPressed: controller.canSend ? onSend : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel({
    required this.approval,
    required this.enabled,
    required this.onAccept,
    required this.onDecline,
  });

  final PendingApproval approval;
  final bool enabled;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF302617),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB86C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            approval.title,
            style: const TextStyle(
              color: Color(0xFFFFD29A),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (approval.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(approval.detail),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                onPressed: enabled ? onDecline : null,
                child: const Text('拒绝'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: enabled ? onAccept : null,
                child: const Text('仅本次允许'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({required this.controller});

  final CodexController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('变更与审批', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            const _InspectorCard(
              icon: Icons.description_outlined,
              title: '文件变更',
              detail: '连接真实任务后，这里会显示 App Server 事件中的文件 Diff。',
            ),
            const SizedBox(height: 10),
            const _InspectorCard(
              icon: Icons.verified_user_outlined,
              title: '权限审批',
              detail: 'MVP 会把命令和文件权限请求集中展示，不在后台自动批准。',
            ),
            const Spacer(),
            _MutedText('当前线程：${controller.activeThreadId ?? '尚未创建'}'),
          ],
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard(this.entry);

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.kind) {
      TimelineKind.user => const Color(0xFF82B1FF),
      TimelineKind.agent => const Color(0xFF68E0B8),
      TimelineKind.command => const Color(0xFFF9C74F),
      TimelineKind.approval => const Color(0xFFFFB86C),
      TimelineKind.error => const Color(0xFFFF8A80),
      TimelineKind.system => const Color(0xFF94A3B8),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111925),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263448)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                SelectableText(entry.detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({this.label = 'OpenAI / App Server'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF162131),
      ),
      child: Row(
        children: [
          const Icon(Icons.forum_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前任务\n$threadId',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorCard extends StatelessWidget {
  const _InspectorCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111925),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263448)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _MutedText(detail),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.data);

  final String data;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
    );
  }
}
