import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

import '../app_controller.dart';
import '../domain/codex_file_change.dart';
import '../domain/codex_plugin.dart';
import '../domain/codex_marketplace.dart';
import '../domain/codex_thread.dart';
import '../domain/pending_approval.dart';
import '../domain/timeline_entry.dart';

class CodexWorkspace extends StatefulWidget {
  const CodexWorkspace({
    required this.controller,
    this.themeMode = ThemeMode.dark,
    this.themePreset = YeknomColorPreset.midnight,
    this.onThemeModeChanged,
    this.onThemePresetChanged,
    super.key,
  });

  final CodexController controller;
  final ThemeMode themeMode;
  final YeknomColorPreset themePreset;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<YeknomColorPreset>? onThemePresetChanged;

  /// 创建承载工作区页面状态的 State 对象。
  /// Creates the State object that owns workspace-page state.
  @override
  State<CodexWorkspace> createState() => _CodexWorkspaceState();
}

class _CodexWorkspaceState extends State<CodexWorkspace> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _timelineScrollController = ScrollController();
  bool _timelineScrollScheduled = false;

  /// 注册控制器监听器，使时间线在内容更新后自动滚动。
  /// Registers the controller listener that scrolls the timeline after updates.
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleTimelineScroll);
  }

  /// 移除监听器并释放编辑、滚动与控制器资源。
  /// Removes listeners and releases composer, scrolling, and controller resources.
  @override
  void dispose() {
    widget.controller.removeListener(_scheduleTimelineScroll);
    _composer.dispose();
    _timelineScrollController.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  /// 在下一帧将时间线平滑滚动到最新内容。
  /// Smoothly scrolls the timeline to the latest content on the next frame.
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

  /// 打开目录选择器并将有效选择交给控制器。
  /// Opens the directory picker and passes a valid selection to the controller.
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

  /// 读取输入框内容、清空编辑器并发送非空任务。
  /// Reads composer content, clears the editor, and sends a nonempty task.
  Future<void> _send() async {
    final prompt = _composer.text;
    if (prompt.trim().isEmpty) return;
    _composer.clear();
    await widget.controller.sendPrompt(prompt);
  }

  /// 显示账户状态以及 ChatGPT 和 API Key 登录入口。
  /// Shows account status plus ChatGPT and API-key login entry points.
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

  /// 显示中转站 Provider 配置对话框并安全提交设置。
  /// Shows the relay-provider dialog and securely submits its settings.
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
          final palette = YeknomPalette.of(context);
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
                    Text(error, style: TextStyle(color: palette.fault)),
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

  /// 探测并显示 Codex CLI 状态，同时提供路径配置入口。
  /// Probes and shows Codex CLI status while offering path configuration.
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

  /// 请求新名称并重命名指定历史线程。
  /// Requests a new name and renames a specified history thread.
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

  /// 确认后归档指定历史线程。
  /// Archives a specified history thread after confirmation.
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

  /// 刷新并显示归档线程，允许用户恢复线程。
  /// Refreshes and shows archived threads, allowing the user to restore one.
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

  /// 显示当前任务收集到的文件变更和统一 Diff。
  /// Shows file changes and unified diff collected for the current task.
  Future<void> _showFileChanges() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => AlertDialog(
          title: const Text('文件变更'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: _FileChangesList(
              changes: widget.controller.fileChanges,
              turnDiff: widget.controller.turnDiff,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  /// 刷新并显示插件管理器，支持本地 marketplace 与启用状态。
  /// Refreshes and shows the plugin manager for local marketplaces and states.
  Future<void> _showPlugins() async {
    await widget.controller.refreshPlugins();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return AlertDialog(
            key: const Key('plugin-manager-dialog'),
            title: const Text('Codex 插件'),
            content: SizedBox(
              width: 640,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('插件由本机 Codex CLI 管理；安装或启停后，请重启运行时并新建任务。'),
                  const SizedBox(height: 12),
                  if (controller.pluginsLoading || controller.pluginSaving)
                    const LinearProgressIndicator(),
                  if (controller.pluginsError case final error?) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      style: TextStyle(color: YeknomPalette.of(context).fault),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: controller.pluginsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : controller.plugins.isEmpty
                        ? const Center(child: Text('没有已安装或可用的插件。'))
                        : ListView.separated(
                            itemCount: controller.plugins.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final plugin = controller.plugins[index];
                              return _PluginTile(
                                plugin: plugin,
                                busy: controller.pluginSaving,
                                onEnabledChanged: (enabled) => controller
                                    .setPluginEnabled(plugin, enabled),
                                onInstall: () =>
                                    controller.installPlugin(plugin),
                                onRemove: () => _removePlugin(plugin),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: controller.pluginSaving ? null : _showAddMarketplace,
                icon: const Icon(Icons.add_link_outlined),
                label: const Text('添加来源'),
              ),
              TextButton.icon(
                onPressed: controller.pluginSaving ? null : _showMarketplaces,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('管理市场'),
              ),
              TextButton.icon(
                onPressed: controller.pluginsLoading || controller.pluginSaving
                    ? null
                    : controller.refreshPlugins,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
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

  /// 输入或选择一个本地/远程 marketplace 来源并交给控制器注册。
  /// Enters or chooses a local/remote marketplace source and registers it.
  Future<void> _showAddMarketplace() async {
    final source = TextEditingController();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加插件市场'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: source,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '本地目录、Git URL 或 owner/repo',
              hintText: 'example-org/codex-plugins',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final path = await getDirectoryPath(
                confirmButtonText: '选择本地 marketplace',
              );
              if (path != null && context.mounted) {
                Navigator.of(context).pop(path);
              }
            },
            child: const Text('选择本地目录'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(source.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    source.dispose();
    if (selected?.trim().isNotEmpty == true) {
      await widget.controller.addPluginMarketplace(selected!);
    }
  }

  /// 刷新并显示已配置 marketplace，支持 Git 更新与移除。
  /// Refreshes and shows configured marketplaces with Git updates and removal.
  Future<void> _showMarketplaces() async {
    await widget.controller.refreshMarketplaces();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final error = controller.marketplacesError;
          return AlertDialog(
            title: const Text('插件市场'),
            content: SizedBox(
              width: 640,
              height: 420,
              child: controller.marketplacesLoading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                  ? Center(child: Text(error))
                  : controller.marketplaces.isEmpty
                  ? const Center(child: Text('尚未配置插件市场。'))
                  : ListView.separated(
                      itemCount: controller.marketplaces.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final marketplace = controller.marketplaces[index];
                        return _MarketplaceTile(
                          marketplace: marketplace,
                          busy: controller.pluginSaving,
                          onUpgrade: () => controller.upgradePluginMarketplace(
                            marketplace.name,
                          ),
                          onRemove: () => _removeMarketplace(marketplace),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton.icon(
                onPressed: controller.pluginSaving
                    ? null
                    : () => controller.upgradePluginMarketplace(null),
                icon: const Icon(Icons.system_update_outlined),
                label: const Text('刷新所有 Git 市场'),
              ),
              TextButton.icon(
                onPressed:
                    controller.marketplacesLoading || controller.pluginSaving
                    ? null
                    : controller.refreshMarketplaces,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
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

  /// 二次确认后移除 marketplace，避免误删已配置来源。
  /// Removes a marketplace after confirmation to avoid accidental source deletion.
  Future<void> _removeMarketplace(CodexMarketplace marketplace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除插件市场？'),
        content: Text('“${marketplace.name}”将不再提供可安装插件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.removePluginMarketplace(marketplace);
    }
  }

  /// 二次确认后卸载插件，连接器授权仍需在 Codex 中单独管理。
  /// Uninstalls a plugin after confirmation; connector authorization remains managed by Codex.
  Future<void> _removePlugin(CodexPlugin plugin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸载插件？'),
        content: Text('“${plugin.name}”的连接器授权不会随卸载自动移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.removePlugin(plugin);
  }

  /// 构建响应控制器状态的工作区主布局。
  /// Builds the main workspace layout in response to controller state.
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
                  themeMode: widget.themeMode,
                  themePreset: widget.themePreset,
                  onThemeModeChanged: widget.onThemeModeChanged,
                  onThemePresetChanged: widget.onThemePresetChanged,
                  onChooseWorkspace: _chooseWorkspace,
                  onStart: controller.startRuntime,
                  onStop: controller.stopRuntime,
                  onAccount: _showAccount,
                  onRelay: _showRelayProvider,
                  onPlugins: _showPlugins,
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
                              onShowFileChanges: _showFileChanges,
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
    required this.themeMode,
    required this.themePreset,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
    required this.onChooseWorkspace,
    required this.onStart,
    required this.onStop,
    required this.onAccount,
    required this.onRelay,
    required this.onPlugins,
    required this.onSetReasoningEffort,
  });

  final CodexController controller;
  final ThemeMode themeMode;
  final YeknomColorPreset themePreset;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<YeknomColorPreset>? onThemePresetChanged;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onAccount;
  final Future<void> Function() onRelay;
  final Future<void> Function() onPlugins;
  final Future<void> Function(ReasoningEffort) onSetReasoningEffort;

  /// 构建包含运行时、账户、Provider 和项目控制的顶部栏。
  /// Builds the top bar with runtime, account, provider, and workspace controls.
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1000;
    final palette = YeknomPalette.of(context);
    final color = switch (controller.status) {
      RuntimeStatus.ready => palette.ack,
      RuntimeStatus.running => palette.active,
      RuntimeStatus.failed => palette.fault,
      _ => palette.muted,
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
            Icon(Icons.auto_awesome, color: palette.ack),
            const SizedBox(width: 10),
            Text('Codex Desk', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 16),
            _StatusPill(label: label, color: color),
            const Spacer(),
            PopupMenuButton<_ThemeAction>(
              tooltip:
                  '主题：${_themeModeLabel(themeMode)} · ${_themePresetLabel(themePreset)}',
              enabled:
                  onThemeModeChanged != null || onThemePresetChanged != null,
              icon: Icon(_themeModeIcon(themeMode)),
              onSelected: (action) {
                switch (action) {
                  case _ThemeAction.system:
                    onThemeModeChanged?.call(ThemeMode.system);
                  case _ThemeAction.light:
                    onThemeModeChanged?.call(ThemeMode.light);
                  case _ThemeAction.dark:
                    onThemeModeChanged?.call(ThemeMode.dark);
                  case _ThemeAction.workbench:
                    onThemePresetChanged?.call(YeknomColorPreset.workbench);
                  case _ThemeAction.cobalt:
                    onThemePresetChanged?.call(YeknomColorPreset.cobalt);
                  case _ThemeAction.orchid:
                    onThemePresetChanged?.call(YeknomColorPreset.orchid);
                  case _ThemeAction.graphite:
                    onThemePresetChanged?.call(YeknomColorPreset.graphite);
                  case _ThemeAction.obsidian:
                    onThemePresetChanged?.call(YeknomColorPreset.obsidian);
                  case _ThemeAction.midnight:
                    onThemePresetChanged?.call(YeknomColorPreset.midnight);
                  case _ThemeAction.blackberry:
                    onThemePresetChanged?.call(YeknomColorPreset.blackberry);
                  case _ThemeAction.sage:
                    onThemePresetChanged?.call(YeknomColorPreset.sage);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<_ThemeAction>(
                  enabled: false,
                  child: Text('显示模式'),
                ),
                CheckedPopupMenuItem(
                  key: const Key('theme-mode-system'),
                  value: _ThemeAction.system,
                  checked: themeMode == ThemeMode.system,
                  child: const Text('跟随系统'),
                ),
                CheckedPopupMenuItem(
                  key: const Key('theme-mode-light'),
                  value: _ThemeAction.light,
                  checked: themeMode == ThemeMode.light,
                  child: const Text('浅色'),
                ),
                CheckedPopupMenuItem(
                  key: const Key('theme-mode-dark'),
                  value: _ThemeAction.dark,
                  checked: themeMode == ThemeMode.dark,
                  child: const Text('深色'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<_ThemeAction>(
                  enabled: false,
                  child: Text('配色'),
                ),
                ..._ThemeAction.values
                    .where((action) => action.preset != null)
                    .map(
                      (action) => CheckedPopupMenuItem(
                        value: action,
                        checked: action.preset == themePreset,
                        child: Text(_themePresetLabel(action.preset!)),
                      ),
                    ),
              ],
            ),
            const SizedBox(width: 4),
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
                itemBuilder: (context) => controller.reasoningEffortOptions
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
                  items: controller.reasoningEffortOptions
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
            IconButton(
              key: const Key('plugin-manager-button'),
              tooltip: '插件管理',
              onPressed: onPlugins,
              icon: const Icon(Icons.extension_outlined),
            ),
            const SizedBox(width: 4),
            if (compact)
              IconButton(
                tooltip: '选择项目',
                onPressed: controller.canChooseWorkspace
                    ? onChooseWorkspace
                    : null,
                icon: const Icon(Icons.folder_open_outlined),
              )
            else
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

/// 展示一个插件的来源、安装状态和可用操作。
/// Displays one plugin's source, install state, and available actions.
class _PluginTile extends StatelessWidget {
  const _PluginTile({
    required this.plugin,
    required this.busy,
    required this.onEnabledChanged,
    required this.onInstall,
    required this.onRemove,
  });

  final CodexPlugin plugin;
  final bool busy;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onInstall;
  final VoidCallback onRemove;

  /// 构建插件状态行，并只为已安装项显示启用开关。
  /// Builds the plugin state row and shows a toggle only for installed items.
  @override
  Widget build(BuildContext context) {
    final details = [
      plugin.sourceLabel,
      if (plugin.version?.isNotEmpty == true) 'v${plugin.version}',
      plugin.installPolicyLabel,
      plugin.authPolicyLabel,
    ].join(' · ');
    return ListTile(
      leading: Icon(
        plugin.installed ? Icons.extension : Icons.extension_outlined,
      ),
      title: Text(plugin.name),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: plugin.installed
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: plugin.enabled,
                  onChanged: busy ? null : onEnabledChanged,
                ),
                IconButton(
                  tooltip: '卸载插件',
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : FilledButton.tonal(
              onPressed: busy ? null : onInstall,
              child: const Text('安装'),
            ),
    );
  }
}

/// 展示 marketplace 来源、类型以及其允许的维护操作。
/// Displays a marketplace source, type, and available maintenance actions.
class _MarketplaceTile extends StatelessWidget {
  const _MarketplaceTile({
    required this.marketplace,
    required this.busy,
    required this.onUpgrade,
    required this.onRemove,
  });

  final CodexMarketplace marketplace;
  final bool busy;
  final VoidCallback onUpgrade;
  final VoidCallback onRemove;

  /// 构建 marketplace 行；只为 Git 来源提供刷新操作。
  /// Builds the marketplace row and exposes refresh only for Git sources.
  @override
  Widget build(BuildContext context) {
    final source = marketplace.source?.isNotEmpty == true
        ? marketplace.source!
        : marketplace.root;
    return ListTile(
      leading: const Icon(Icons.storefront_outlined),
      title: Text(marketplace.name),
      subtitle: Text(
        '${marketplace.sourceTypeLabel} · $source',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (marketplace.sourceType == 'git')
            IconButton(
              tooltip: '刷新 Git 市场',
              onPressed: busy ? null : onUpgrade,
              icon: const Icon(Icons.system_update_outlined),
            ),
          IconButton(
            tooltip: '移除插件市场',
            onPressed: busy ? null : onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
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

  /// 构建工作区选择、线程历史和 CLI 配置侧栏。
  /// Builds the sidebar for workspace selection, thread history, and CLI setup.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
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
                key: const Key('workspace-picker-surface'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
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
    required this.onShowFileChanges,
  });

  final CodexController controller;
  final TextEditingController composer;
  final ScrollController timelineScrollController;
  final Future<void> Function() onSend;
  final Future<void> Function() onShowFileChanges;

  /// 构建时间线、审批提示和任务输入区域。
  /// Builds the timeline, approval prompt, and task composer area.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showProvider = constraints.maxWidth >= 360;
              final showSandbox = constraints.maxWidth >= 560;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      '任务控制台',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (showProvider) ...[
                    _ProviderChip(
                      label: '${controller.providerLabel} / App Server',
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (showSandbox) ...[
                    const _ProviderChip(label: 'workspace-write'),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    tooltip: '查看文件变更',
                    onPressed: onShowFileChanges,
                    icon: const Icon(Icons.difference_outlined, size: 19),
                  ),
                ],
              );
            },
          ),
        ),
        if (controller.lastError case final error?)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.fault.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(error, style: TextStyle(color: palette.fault)),
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
        _ComposerPanel(
          controller: controller,
          composer: composer,
          onSend: onSend,
        ),
      ],
    );
  }
}

class _ComposerPanel extends StatelessWidget {
  const _ComposerPanel({
    required this.controller,
    required this.composer,
    required this.onSend,
  });

  final CodexController controller;
  final TextEditingController composer;
  final Future<void> Function() onSend;

  int get _fileChangeCount => controller.entries
      .where((entry) => entry.title == '文件变更')
      .fold(0, (total, entry) => total + entry.detail.split('\n').length);

  String get _activityLabel {
    if (controller.status == RuntimeStatus.running) {
      final count = _fileChangeCount;
      return count == 0 ? '正在处理任务' : '正在处理 · $count 个文件已变更';
    }
    return controller.status == RuntimeStatus.ready ? '任务已就绪' : '等待运行时连接';
  }

  /// 构建支持 Enter 发送、Shift+Enter 换行的任务输入面板。
  /// Builds the task composer that sends with Enter and inserts lines with Shift+Enter.
  @override
  Widget build(BuildContext context) {
    final model = controller.relayProvider?.model ?? 'Codex';
    final effort = controller.reasoningEffort.label;
    final palette = YeknomPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.activeThreadId != null ||
              controller.status == RuntimeStatus.running) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: controller.status == RuntimeStatus.running
                            ? palette.active
                            : palette.muted,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _activityLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.muted),
                  ),
                ],
              ),
            ),
          ],
          Container(
            constraints: const BoxConstraints(minHeight: 126),
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 10),
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.controlBorder),
            ),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 64,
                    maxHeight: 124,
                  ),
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
                      style: TextStyle(color: palette.trace),
                      decoration: InputDecoration.collapsed(
                        hintText: '随心输入',
                        hintStyle: TextStyle(color: palette.muted),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final showAttachment = constraints.maxWidth >= 420;
                    final showApproval = constraints.maxWidth >= 260;
                    final showApprovalLabel = constraints.maxWidth >= 360;
                    final showModel = constraints.maxWidth >= 190;
                    return Row(
                      children: [
                        if (showAttachment)
                          IconButton(
                            tooltip: '附加内容（即将支持）',
                            onPressed: null,
                            icon: const Icon(Icons.add, size: 20),
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
                                  const Icon(
                                    Icons.verified_user_outlined,
                                    size: 16,
                                  ),
                                  if (showApprovalLabel) ...[
                                    const SizedBox(width: 5),
                                    Text(
                                      controller.approvalMode ==
                                              ApprovalMode.autoApprove
                                          ? '自动批准'
                                          : '帮助批准',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        if (showModel) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$model · 推理$effort',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.muted),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ] else
                          const Spacer(),
                        if (controller.canStop)
                          IconButton.filled(
                            tooltip: '停止当前任务',
                            onPressed: controller.stopCurrentTurn,
                            style: IconButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                            ),
                            icon: const Icon(Icons.stop, size: 19),
                          )
                        else
                          IconButton.filled(
                            tooltip: '发送任务',
                            onPressed: controller.canSend ? onSend : null,
                            style: IconButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                            ),
                            icon: const Icon(Icons.arrow_upward, size: 19),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
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

  /// 构建当前服务器审批请求及其允许、拒绝操作。
  /// Builds the current server approval request with allow and decline actions.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.signalSelected,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            approval.title,
            style: TextStyle(
              color: palette.signal,
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

  /// 构建审批模式和文件变更的桌面检查器面板。
  /// Builds the desktop inspector panel for approval mode and file changes.
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
              icon: Icons.verified_user_outlined,
              title: '权限审批',
              detail: '审批请求会集中展示；自动模式会直接响应并记录到时间线。',
            ),
            const SizedBox(height: 16),
            Text('文件变更', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Expanded(
              child: _FileChangesList(
                changes: controller.fileChanges,
                turnDiff: controller.turnDiff,
              ),
            ),
            const SizedBox(height: 12),
            _MutedText('当前线程：${controller.activeThreadId ?? '尚未创建'}'),
          ],
        ),
      ),
    );
  }
}

class _FileChangesList extends StatelessWidget {
  const _FileChangesList({required this.changes, required this.turnDiff});

  final List<CodexFileChange> changes;
  final String? turnDiff;

  /// 构建任务统一 Diff 与单文件变更的可展开列表。
  /// Builds an expandable list for the task's unified diff and individual file changes.
  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty && (turnDiff == null || turnDiff!.isEmpty)) {
      return const _MutedText('任务执行后，AI 修改的文件和逐行 Diff 会显示在这里。');
    }
    return ListView(
      children: [
        if (turnDiff case final diff?)
          _DiffExpansionTile(
            title: '本次任务完整 Diff',
            subtitle: '来自 Codex App Server',
            diff: diff,
          ),
        ...changes.map(
          (change) => _DiffExpansionTile(
            title: change.path,
            subtitle: change.kind,
            diff: change.diff,
          ),
        ),
      ],
    );
  }
}

class _DiffExpansionTile extends StatelessWidget {
  const _DiffExpansionTile({
    required this.title,
    required this.subtitle,
    required this.diff,
  });

  final String title;
  final String subtitle;
  final String diff;

  /// 构建可展开的单个 Diff 展示项。
  /// Builds one expandable diff presentation item.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(bottom: 10),
      leading: const Icon(Icons.description_outlined, size: 18),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: diff.isEmpty
              ? const _MutedText('App Server 未提供可显示的 Diff。')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText.rich(
                    TextSpan(children: _diffSpans(palette, diff)),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// 按 unified Diff 行类型与当前主题语义色为文本片段分配颜色。
  /// Assigns colors to text spans using unified-diff line types and theme semantics.
  List<TextSpan> _diffSpans(YeknomPalette palette, String value) {
    return value
        .split('\n')
        .map((line) {
          final color = switch (line) {
            _ when line.startsWith('+++') || line.startsWith('---') =>
              palette.muted,
            _ when line.startsWith('+') => palette.ack,
            _ when line.startsWith('-') => palette.fault,
            _ when line.startsWith('@@') => palette.active,
            _ => palette.trace,
          };
          return TextSpan(
            text: '$line\n',
            style: TextStyle(color: color),
          );
        })
        .toList(growable: false);
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry(this.entry);

  final TimelineEntry entry;

  /// 按时间线条目类型构建消息或系统事件视图。
  /// Builds a message or system-event view based on the timeline entry kind.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (entry.kind == TimelineKind.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(entry.detail),
        ),
      );
    }

    final color = switch (entry.kind) {
      TimelineKind.agent => palette.ack,
      TimelineKind.command => palette.warning,
      TimelineKind.tool => palette.active,
      TimelineKind.approval => palette.signal,
      TimelineKind.error => palette.fault,
      TimelineKind.system => palette.muted,
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

  /// 构建表示运行时状态的紧凑彩色标签。
  /// Builds a compact colored pill representing runtime status.
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

  /// 构建 Provider 或运行时边界的紧凑说明标签。
  /// Builds a compact label for a provider or runtime boundary.
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

  /// 构建带有恢复、重命名和归档操作的历史线程项。
  /// Builds a history-thread item with resume, rename, and archive actions.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Material(
      color: selected ? palette.selected : palette.raised,
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
                color: selected ? palette.ack : null,
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

enum _ThemeAction {
  system,
  light,
  dark,
  workbench,
  cobalt,
  orchid,
  graphite,
  obsidian,
  midnight,
  blackberry,
  sage;

  /// 返回对应配色预设；显示模式操作没有预设。
  /// Returns the corresponding color preset; display-mode actions have none.
  YeknomColorPreset? get preset => switch (this) {
    _ThemeAction.workbench => YeknomColorPreset.workbench,
    _ThemeAction.cobalt => YeknomColorPreset.cobalt,
    _ThemeAction.orchid => YeknomColorPreset.orchid,
    _ThemeAction.graphite => YeknomColorPreset.graphite,
    _ThemeAction.obsidian => YeknomColorPreset.obsidian,
    _ThemeAction.midnight => YeknomColorPreset.midnight,
    _ThemeAction.blackberry => YeknomColorPreset.blackberry,
    _ThemeAction.sage => YeknomColorPreset.sage,
    _ => null,
  };
}

/// 返回显示模式的本地化名称。
/// Returns the localized name for a display mode.
String _themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

/// 返回显示模式在顶部栏中使用的图标。
/// Returns the icon used for a display mode in the top bar.
IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

/// 返回 UI Kit 配色预设的本地化名称。
/// Returns the localized name for a UI Kit color preset.
String _themePresetLabel(YeknomColorPreset preset) => switch (preset) {
  YeknomColorPreset.workbench => '工作台',
  YeknomColorPreset.cobalt => '钴蓝',
  YeknomColorPreset.orchid => '兰紫',
  YeknomColorPreset.graphite => '石墨',
  YeknomColorPreset.obsidian => '黑曜',
  YeknomColorPreset.midnight => '午夜',
  YeknomColorPreset.blackberry => '黑莓',
  YeknomColorPreset.sage => '鼠尾草',
};

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

  /// 构建带恢复操作与进行状态的归档线程项。
  /// Builds an archived-thread item with restore action and progress state.
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

  /// 构建检查器中带图标、标题和说明的静态信息卡。
  /// Builds a static inspector card with icon, title, and description.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.module,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: palette.muted),
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

  /// 构建使用低强调颜色的辅助说明文本。
  /// Builds helper text using a low-emphasis color.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Text(data, style: TextStyle(color: palette.muted, fontSize: 12));
  }
}
