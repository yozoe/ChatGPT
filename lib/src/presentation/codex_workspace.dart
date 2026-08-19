import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    try {
      final path = await getDirectoryPath(confirmButtonText: '选择项目');
      if (path != null && path.trim().isNotEmpty) {
        await widget.controller.selectWorkspace(path);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
    }
  }

  Future<void> _send() async {
    final prompt = _composer.text;
    if (prompt.trim().isEmpty) return;
    _composer.clear();
    await widget.controller.sendPrompt(prompt);
  }

  Future<void> _showAccount() async {
    final apiKey = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return AlertDialog(
            title: const Text('账户与登录'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前状态：${controller.authLabel}'),
                  if (controller.accountEmail case final email?) ...[
                    const SizedBox(height: 4),
                    Text(email),
                  ],
                  const SizedBox(height: 16),
                  if (!controller.canStopRuntime)
                    const Text('请先选择项目并启动本地运行时。')
                  else ...[
                    FilledButton.icon(
                      onPressed: controller.loginInProgress
                          ? null
                          : controller.startChatgptLogin,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('使用 ChatGPT 登录'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiKey,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'OpenAI API Key',
                        hintText: 'sk-…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) async {
                        await controller.loginWithApiKey(value);
                        apiKey.clear();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '密钥不会被此应用写入项目或日志；它会交给本地 Codex 运行时处理。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: controller.loginInProgress
                          ? null
                          : () async {
                              await controller.loginWithApiKey(apiKey.text);
                              apiKey.clear();
                            },
                      child: const Text('使用 API Key 登录'),
                    ),
                    if (controller.loginUrl case final authUrl?) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        authUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          final opened = await launchUrl(
                            Uri.parse(authUrl),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('无法打开浏览器。')),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('在浏览器中打开登录页'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
    apiKey.dispose();
  }

  Future<void> _showRelayProvider() async {
    final current = widget.controller.relayProvider;
    final baseUrl = TextEditingController(text: current?.baseUrl ?? '');
    final model = TextEditingController(text: current?.model ?? '');
    final apiKey = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return AlertDialog(
            title: const Text('中转站 Provider'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('仅支持 Responses API 与 SSE 流式响应兼容的服务。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: baseUrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://relay.example.com/v1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: model,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      hintText: 'relay-model-name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: apiKey,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: current == null
                          ? '中转站 API Key'
                          : '中转站 API Key（留空则保留已存密钥）',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '凭据只保存在 macOS Keychain。Provider 配置仅随本应用新建的 Thread 发送，不会修改 ~/.codex/config.toml。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (controller.relayError case final error?) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      style: const TextStyle(color: Color(0xFFFFB4AB)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (current != null)
                TextButton(
                  onPressed: controller.relaySaving
                      ? null
                      : () => controller.clearRelayProvider(),
                  child: const Text('移除配置'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: controller.relaySaving
                    ? null
                    : () async {
                        await controller.saveRelayProvider(
                          baseUrl: baseUrl.text,
                          model: model.text,
                          apiKey: apiKey.text,
                        );
                        apiKey.clear();
                        if (controller.relayError == null && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                child: Text(controller.relaySaving ? '保存中…' : '保存并使用'),
              ),
            ],
          );
        },
      ),
    );
    baseUrl.dispose();
    model.dispose();
    apiKey.dispose();
  }

  Future<void> _showRuntime() async {
    await widget.controller.inspectRuntime();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final probe = controller.runtimeProbe;
          return AlertDialog(
            title: const Text('Codex CLI 运行时'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.runtimeChecking)
                    const LinearProgressIndicator()
                  else if (probe?.isAvailable == true) ...[
                    const Text('已检测到可用的 Codex CLI。'),
                    const SizedBox(height: 8),
                    SelectableText(probe!.executablePath ?? ''),
                    if (probe.version?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        probe.version!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ] else ...[
                    Text(controller.runtimeError ?? '尚未检测到 Codex CLI。'),
                    const SizedBox(height: 12),
                    const Text('可在终端执行以下官方安装命令：'),
                    const SizedBox(height: 6),
                    const SelectableText(
                      'curl -fsSL https://chatgpt.com/codex/install.sh | sh',
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '选择的路径仅保存为本应用设置；启动时会再次验证，不依赖 Finder 的 PATH。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    controller.canConfigureRuntime &&
                        !controller.runtimeChecking
                    ? () async {
                        final file = await openFile(
                          confirmButtonText: '使用此 Codex CLI',
                        );
                        if (file != null) {
                          await controller.setRuntimeExecutable(file.path);
                        }
                      }
                    : null,
                child: const Text('选择可执行文件'),
              ),
              if (controller.canConfigureRuntime)
                TextButton(
                  onPressed: controller.runtimeChecking
                      ? null
                      : controller.resetRuntimeExecutable,
                  child: const Text('恢复自动检测'),
                ),
              TextButton(
                onPressed: controller.runtimeChecking
                    ? null
                    : controller.inspectRuntime,
                child: const Text('重新检测'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
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
                  onAccount: _showAccount,
                  onRelay: _showRelayProvider,
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
                            onConfigureRuntime: _showRuntime,
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
    required this.onAccount,
    required this.onRelay,
  });

  final CodexController controller;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onAccount;
  final Future<void> Function() onRelay;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1000;
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
            if (compact)
              IconButton(
                tooltip: '账户：${controller.authLabel}',
                onPressed: onAccount,
                icon: const Icon(Icons.person_outline),
              )
            else
              TextButton.icon(
                onPressed: onAccount,
                icon: const Icon(Icons.person_outline),
                label: Text(controller.authLabel),
              ),
            const SizedBox(width: 8),
            if (compact)
              IconButton(
                tooltip: 'Provider：${controller.providerLabel}',
                onPressed: onRelay,
                icon: const Icon(Icons.route_outlined),
              )
            else
              TextButton.icon(
                onPressed: onRelay,
                icon: const Icon(Icons.route_outlined),
                label: Text(controller.providerLabel),
              ),
            const SizedBox(width: 8),
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
  const _Sidebar({
    required this.controller,
    required this.onChooseWorkspace,
    required this.onConfigureRuntime,
  });

  final CodexController controller;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onConfigureRuntime;

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
            OutlinedButton.icon(
              onPressed: onConfigureRuntime,
              icon: const Icon(Icons.memory_outlined, size: 18),
              label: const Text('Codex CLI'),
            ),
            const SizedBox(height: 10),
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
              _ProviderChip(label: '${controller.providerLabel} / App Server'),
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
