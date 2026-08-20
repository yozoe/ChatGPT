import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../domain/codex_thread.dart';
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
  final ScrollController _timelineScrollController = ScrollController();
  bool _timelineScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleTimelineScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleTimelineScroll);
    _composer.dispose();
    _timelineScrollController.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  void _scheduleTimelineScroll() {
    if (!mounted || _timelineScrollScheduled) return;
    _timelineScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineScrollScheduled = false;
      if (!mounted || !_timelineScrollController.hasClients) return;
      final position = _timelineScrollController.position;
      position.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
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

  Future<void> _renameThread(CodexThread thread) async {
    final name = TextEditingController(text: thread.name ?? thread.preview);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名任务'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: '任务名称'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(name.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    name.dispose();
    if (nextName != null && nextName.trim().isNotEmpty) {
      await widget.controller.renameThread(thread, nextName);
    }
  }

  Future<void> _archiveThread(CodexThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档任务？'),
        content: Text('“${thread.title}”将从当前列表隐藏，但可以在后续归档视图中恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.archiveThread(thread);
  }

  Future<void> _showArchivedThreads() async {
    await widget.controller.refreshArchivedThreads();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return AlertDialog(
            title: const Text('已归档任务'),
            content: SizedBox(
              width: 480,
              height: 420,
              child: switch ((
                controller.archivedThreadsLoading,
                controller.archivedThreadsError,
                controller.archivedThreads,
              )) {
                (true, _, _) => const Center(
                  child: CircularProgressIndicator(),
                ),
                (_, final String error, _) => Center(child: Text(error)),
                (_, _, final List<CodexThread> threads) when threads.isEmpty =>
                  const Center(child: Text('暂无归档任务。')),
                (_, _, final List<CodexThread> threads) => ListView.separated(
                  itemCount: threads.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final thread = threads[index];
                    return _ArchivedThreadTile(
                      thread: thread,
                      enabled:
                          controller.status == RuntimeStatus.ready &&
                          !controller.isUnarchivingThread(thread.id),
                      restoring: controller.isUnarchivingThread(thread.id),
                      onRestore: () => controller.unarchiveThread(thread),
                    );
                  },
                ),
              },
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
                  onSetReasoningEffort: controller.setReasoningEffort,
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
                            onRenameThread: _renameThread,
                            onArchiveThread: _archiveThread,
                            onShowArchivedThreads: _showArchivedThreads,
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _ConversationPane(
                              controller: controller,
                              composer: _composer,
                              timelineScrollController:
                                  _timelineScrollController,
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
    required this.onSetReasoningEffort,
  });

  final CodexController controller;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onAccount;
  final Future<void> Function() onRelay;
  final Future<void> Function(ReasoningEffort) onSetReasoningEffort;

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
            if (compact)
              PopupMenuButton<ReasoningEffort>(
                tooltip: '推理强度：${controller.reasoningEffort.label}',
                icon: const Icon(Icons.psychology_outlined),
                onSelected: onSetReasoningEffort,
                itemBuilder: (context) => ReasoningEffort.values
                    .map(
                      (effort) => CheckedPopupMenuItem(
                        value: effort,
                        checked: controller.reasoningEffort == effort,
                        child: Text('推理强度：${effort.label}'),
                      ),
                    )
                    .toList(growable: false),
              )
            else
              DropdownButtonHideUnderline(
                child: DropdownButton<ReasoningEffort>(
                  value: controller.reasoningEffort,
                  borderRadius: BorderRadius.circular(10),
                  icon: const Icon(Icons.psychology_outlined, size: 18),
                  onChanged: (value) {
                    if (value != null) onSetReasoningEffort(value);
                  },
                  items: ReasoningEffort.values
                      .map(
                        (effort) => DropdownMenuItem(
                          value: effort,
                          child: Text('推理：${effort.label}'),
                        ),
                      )
                      .toList(growable: false),
                ),
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
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onShowArchivedThreads,
  });

  final CodexController controller;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onConfigureRuntime;
  final Future<void> Function(CodexThread thread) onRenameThread;
  final Future<void> Function(CodexThread thread) onArchiveThread;
  final Future<void> Function() onShowArchivedThreads;

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
                IconButton(
                  tooltip: '刷新任务列表',
                  onPressed: controller.canSend && !controller.threadsLoading
                      ? controller.refreshThreads
                      : null,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                IconButton(
                  tooltip: '已归档任务',
                  onPressed: controller.canSend ? onShowArchivedThreads : null,
                  icon: const Icon(Icons.inventory_2_outlined, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (controller.threadsLoading)
              const LinearProgressIndicator(minHeight: 2)
            else if (controller.threadsError case final error?)
              _MutedText(error)
            else if (controller.threads.isEmpty)
              const _MutedText('暂无历史任务；发送第一条消息后会创建。')
            else
              Expanded(
                child: ListView.separated(
                  itemCount: controller.threads.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final thread = controller.threads[index];
                    return _HistoryThreadTile(
                      thread: thread,
                      selected: controller.activeThreadId == thread.id,
                      enabled: controller.status == RuntimeStatus.ready,
                      onTap: () => controller.resumeThread(thread),
                      onRename: () => onRenameThread(thread),
                      onArchive: () => onArchiveThread(thread),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
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
    required this.timelineScrollController,
    required this.onSend,
  });

  final CodexController controller;
  final TextEditingController composer;
  final ScrollController timelineScrollController;
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
            controller: timelineScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            itemCount: controller.entries.length,
            separatorBuilder: (_, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            itemBuilder: (context, index) =>
                _TimelineEntry(controller.entries[index]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      unawaited(onSend());
                    },
                  },
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
            Text('审批模式', style: Theme.of(context).textTheme.labelLarge),
            DropdownButton<ApprovalMode>(
              value: controller.approvalMode,
              isExpanded: true,
              items: ApprovalMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(growable: false),
              onChanged: (mode) {
                if (mode != null) controller.setApprovalMode(mode);
              },
            ),
            _MutedText(
              controller.approvalMode == ApprovalMode.autoApprove
                  ? '自动批准命令、文件变更和额外权限请求。'
                  : '每次请求都会显示批准与拒绝按钮。',
            ),
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
              detail: '审批请求会集中展示；自动模式会直接响应并记录到时间线。',
            ),
            const Spacer(),
            _MutedText('当前线程：${controller.activeThreadId ?? '尚未创建'}'),
          ],
        ),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry(this.entry);

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.kind == TimelineKind.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF20242B),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(entry.detail),
        ),
      );
    }

    final color = switch (entry.kind) {
      TimelineKind.agent => const Color(0xFF68E0B8),
      TimelineKind.command => const Color(0xFFF9C74F),
      TimelineKind.tool => const Color(0xFFC4A7FF),
      TimelineKind.approval => const Color(0xFFFFB86C),
      TimelineKind.error => const Color(0xFFFF8A80),
      TimelineKind.system => const Color(0xFF94A3B8),
      TimelineKind.user => throw StateError('Handled above.'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.title,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        if (entry.detail.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(entry.detail),
        ],
      ],
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

class _HistoryThreadTile extends StatelessWidget {
  const _HistoryThreadTile({
    required this.thread,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
  });

  final CodexThread thread;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF1D3343) : const Color(0xFF162131),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              Icon(
                selected ? Icons.forum : Icons.forum_outlined,
                size: 17,
                color: selected ? const Color(0xFF68E0B8) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (thread.status case final status?)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: _MutedText(status),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<_ThreadAction>(
                tooltip: '任务选项',
                enabled: enabled,
                onSelected: (action) {
                  switch (action) {
                    case _ThreadAction.rename:
                      onRename();
                    case _ThreadAction.archive:
                      onArchive();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ThreadAction.rename,
                    child: Text('重命名'),
                  ),
                  PopupMenuItem(
                    value: _ThreadAction.archive,
                    child: Text('归档'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ThreadAction { rename, archive }

class _ArchivedThreadTile extends StatelessWidget {
  const _ArchivedThreadTile({
    required this.thread,
    required this.enabled,
    required this.restoring,
    required this.onRestore,
  });

  final CodexThread thread;
  final bool enabled;
  final bool restoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: thread.status == null ? null : Text(thread.status!),
      trailing: TextButton.icon(
        onPressed: enabled ? onRestore : null,
        icon: restoring
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.unarchive_outlined, size: 18),
        label: Text(restoring ? '恢复中' : '恢复'),
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
