import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

import '../app_controller.dart';
import '../domain/codex_file_change.dart';
import '../domain/git_project_status.dart';
import '../domain/codex_plugin.dart';
import '../domain/codex_skill.dart';
import '../domain/codex_marketplace.dart';
import '../domain/codex_thread.dart';
import '../domain/pending_approval.dart';
import '../domain/task_plan.dart';
import '../domain/timeline_entry.dart';
import '../domain/workspace_configuration.dart';
import '../services/clipboard_file_reader.dart';

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return const [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  ].any(lower.endsWith);
}

class CodexWorkspace extends ConsumerStatefulWidget {
  const CodexWorkspace({
    this.controller,
    this.themeMode = ThemeMode.dark,
    this.themePreset = YeknomColorPreset.midnight,
    this.onThemeModeChanged,
    this.onThemePresetChanged,
    super.key,
  });

  /// 测试或嵌入式场景可显式注入控制器；正常运行时从 Riverpod 读取共享实例。
  /// Tests and embedded callers may inject a controller; normal execution reads the shared Riverpod instance.
  final CodexController? controller;
  final ThemeMode themeMode;
  final YeknomColorPreset themePreset;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<YeknomColorPreset>? onThemePresetChanged;

  /// 创建承载工作区页面状态的 State 对象。
  /// Creates the State object that owns workspace-page state.
  @override
  ConsumerState<CodexWorkspace> createState() => _CodexWorkspaceState();
}

class _CodexWorkspaceState extends ConsumerState<CodexWorkspace> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _timelineScrollController = ScrollController();
  bool _timelineScrollScheduled = false;
  late final CodexController _controller;

  /// 注册控制器监听器，使时间线在内容更新后自动滚动。
  /// Registers the controller listener that scrolls the timeline after updates.
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ref.read(codexControllerProvider)!;
    _controller.addListener(_handleControllerUpdate);
  }

  /// 移除监听器并释放编辑、滚动与控制器资源。
  /// Removes listeners and releases composer, scrolling, and controller resources.
  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
    _composer.dispose();
    _timelineScrollController.dispose();
    // 显式注入的控制器沿用原有由工作区释放的约定；Provider 创建的
    // 控制器由 ProviderScope 统一释放。
    // Explicitly injected controllers retain the original workspace ownership;
    // Provider-created controllers are disposed by ProviderScope.
    if (widget.controller != null) _controller.dispose();
    super.dispose();
  }

  /// 响应控制器更新；显式注入时由工作区重建，Provider 场景仍由 ref.watch 重建。
  /// Responds to controller updates; the workspace rebuilds explicit injections while ref.watch rebuilds provider state.
  void _handleControllerUpdate() {
    if (widget.controller != null && mounted) setState(() {});
    _scheduleTimelineScroll();
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

  /// 打开目录选择器并将所选目录注册为新的可切换工作区。
  /// Opens the directory picker and registers the selected directory as a new switchable workspace.
  Future<bool> _createWorkspace() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '新建工作区');
      if (path != null && path.trim().isNotEmpty) {
        return await _controller.createWorkspace(path);
      }
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
    }
    return false;
  }

  /// 选择并添加一个附加工作区目录。
  /// Selects and adds an additional workspace directory.
  Future<bool> _addWorkspaceDirectory() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '添加目录');
      if (path != null && path.trim().isNotEmpty) {
        await _controller.addWorkspaceRoot(path);
        return true;
      }
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
    }
    return false;
  }

  /// 展示可切换工作区列表，以及当前工作区的主目录与附加目录。
  /// Shows switchable workspaces plus the current workspace's primary and additional directories.
  Future<void> _showWorkspaceDirectories() async {
    await showDialog<void>(
      context: context,
      // 运行时切换与目录保存都可能在弹窗打开期间完成，按钮状态必须随控制器实时更新。
      // Runtime transitions and directory saves may finish while open, so actions must rebuild live.
      builder: (dialogContext) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final primary = _controller.workspacePath;
          final additional = _controller.additionalWorkspacePaths;
          final workspaces = _controller.workspaceConfigurations;
          return AlertDialog(
            key: const Key('workspace-directories-dialog'),
            title: const Text('工作区'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('每个工作区会独立保存主目录、附加目录和本地历史。新建或切换后会自动连接运行时。'),
                    if (!_controller.canChangePrimaryWorkspace) ...[
                      const SizedBox(height: 8),
                      const _MutedText('当前任务执行完成后可以新建或切换工作区；附加目录仍可直接调整。'),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          '已保存工作区',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 8),
                        Text('${workspaces.length}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (workspaces.isEmpty)
                      const _WorkspaceDirectoryTile(
                        key: Key('saved-workspaces-empty'),
                        path: null,
                        label: '暂无工作区',
                        description: '点击“新建工作区”选择主目录',
                        primary: true,
                      )
                    else
                      ...workspaces.map((workspace) {
                        final active = workspace.primaryPath == primary;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _WorkspaceDirectoryTile(
                            key: ValueKey(
                              'workspace-profile-${workspace.primaryPath}',
                            ),
                            path: workspace.primaryPath,
                            label: active ? '当前工作区' : '工作区',
                            description: workspace.additionalPaths.isEmpty
                                ? '仅主目录'
                                : '${workspace.additionalPaths.length} 个附加目录',
                            primary: active,
                            trailing: active
                                ? const Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text('当前'),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        key: ValueKey(
                                          'switch-workspace-${workspace.primaryPath}',
                                        ),
                                        onPressed:
                                            _controller
                                                .canChangePrimaryWorkspace
                                            ? () => _controller
                                                  .selectWorkspaceAndReconnect(
                                                    workspace.primaryPath,
                                                  )
                                            : null,
                                        child: const Text('切换'),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'forget-workspace-${workspace.primaryPath}',
                                        ),
                                        tooltip: '从列表移除（不会删除目录或历史）',
                                        onPressed: () =>
                                            _controller.forgetWorkspace(
                                              workspace.primaryPath,
                                            ),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      }),
                    const SizedBox(height: 20),
                    Text(
                      '当前工作区目录',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    _WorkspaceDirectoryTile(
                      key: const Key('primary-workspace-directory'),
                      path: primary,
                      label: '主目录',
                      description: '配置、历史、Git 和默认工作位置',
                      primary: true,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          '附加目录',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 8),
                        Text('${additional.length}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (additional.isEmpty)
                      const _WorkspaceDirectoryTile(
                        key: Key('additional-workspaces-empty'),
                        path: null,
                        label: '暂无附加目录',
                        description: '添加后，新任务可以同时访问这些目录',
                      )
                    else
                      ...additional.map(
                        (path) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _WorkspaceDirectoryTile(
                            key: ValueKey('additional-workspace-$path'),
                            path: path,
                            label: '附加目录',
                            description: '供后续新任务访问',
                            trailing: IconButton(
                              tooltip: '移除附加目录',
                              onPressed: () async {
                                await _controller.removeWorkspaceRoot(path);
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
              OutlinedButton.icon(
                key: const Key('add-workspace-directory-button'),
                onPressed: primary != null
                    ? () async {
                        await _addWorkspaceDirectory();
                      }
                    : null,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('添加目录'),
              ),
              FilledButton.icon(
                key: const Key('create-workspace-button'),
                onPressed: _controller.canChangePrimaryWorkspace
                    ? _createWorkspace
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('新建工作区'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 读取输入框内容、清空编辑器并发送非空任务。
  /// Reads composer content, clears the editor, and sends a nonempty task.
  Future<bool> _send(_ComposerSubmission submission) async {
    final rawPrompt = _composer.text.trim();
    if (rawPrompt.isEmpty && !submission.hasContext) return false;
    final contextLines = <String>[];
    final additionalInput = <Map<String, dynamic>>[];
    final skillNames = <String>{};
    final selectedSkills = [...submission.skills];
    if (submission.recordSkill) {
      final creator = _controller.skills
          .where((skill) => skill.name == 'skill-creator')
          .firstOrNull;
      if (creator != null) selectedSkills.add(creator);
      contextLines.add('请把本次任务的有效流程整理成一个可复用的 Codex 技能。');
    }
    for (final skill in selectedSkills) {
      if (!skillNames.add(skill.name)) continue;
      additionalInput.add({
        'type': 'skill',
        'name': skill.name,
        'path': skill.path,
      });
    }
    for (final attachment in submission.attachments) {
      final path = attachment.path;
      if (!attachment.isDirectory && _isImagePath(path)) {
        additionalInput.add({'type': 'localImage', 'path': path});
      } else {
        contextLines.add('附加路径：$path');
      }
    }
    if (submission.includeWorkspace && _controller.workspacePath != null) {
      contextLines.add('显式附加当前项目：${_controller.workspacePath}');
    }
    final skillPrefix = skillNames.map((name) => '\$$name').join(' ');
    final promptParts = <String>[
      if (skillPrefix.isNotEmpty) skillPrefix,
      rawPrompt.isEmpty ? '请分析已附加的内容。' : rawPrompt,
      if (contextLines.isNotEmpty) '\n${contextLines.join('\n')}',
    ];
    final sent = await _controller.sendPrompt(
      promptParts.join(' ').trim(),
      additionalInput: additionalInput,
      goal: submission.goal,
      planMode: submission.planMode,
    );
    if (sent) _composer.clear();
    return sent;
  }

  /// Sends text entered while a turn is running as a direction adjustment.
  /// 运行中 Composer 的纯文本输入通过 `turn/steer` 发送到当前活动 turn。
  Future<bool> _steer(String prompt) => _controller.steerCurrentTurn(prompt);

  /// Opens a focused editor for steering the currently running turn.
  /// 打开“调整方向”编辑器，将新的指示发送到当前活动 turn。
  Future<void> _adjustDirection(String originalPrompt) async {
    var draft = '';
    final direction = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('adjust-direction-dialog'),
        title: const Text('调整方向'),
        content: SizedBox(
          width: 520,
          child: TextFormField(
            key: const Key('adjust-direction-field'),
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            onChanged: (value) => draft = value,
            decoration: InputDecoration(
              hintText: '告诉 Codex 接下来应该怎么调整…',
              helperText: '原指令：${originalPrompt.trim()}',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('send-adjust-direction'),
            onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
            child: const Text('发送调整'),
          ),
        ],
      ),
    );
    if (direction == null || direction.trim().isEmpty || !mounted) return;
    await _controller.steerCurrentTurn(direction);
  }

  /// 将当前项目的本地历史导出到用户选择的 JSON 文件；文件不包含 API Key。
  /// Exports the current workspace's local history to a user-selected JSON file without API keys.
  Future<void> _exportConversationHistory() async {
    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Codex Desk 历史', extensions: ['json']),
        ],
        suggestedName: 'codex-desk-history.json',
        confirmButtonText: '导出历史',
      );
      if (location == null) return;
      final content = _controller.exportConversationHistory();
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
        name: 'codex-desk-history.json',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本地历史已导出。文件可能包含对话和 Diff，请妥善保管。')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出历史失败：$error')));
      }
    }
  }

  /// 选择并确认导入历史 JSON 到当前项目的本地缓存。
  /// Selects and confirms importing history JSON into the current workspace cache.
  Future<void> _importConversationHistory() async {
    try {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Codex Desk 历史', extensions: ['json']),
        ],
        confirmButtonText: '导入历史',
      );
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入本地历史？'),
          content: const Text(
            '导入会替换当前项目在 Codex Desk 中缓存的任务列表、置顶状态、对话和 Diff。不会恢复 App Server 原始任务，也不会修改项目文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _controller.importConversationHistory(
        await selected.readAsString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本地历史已导入到当前项目。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入历史失败：$error')));
      }
    }
  }

  /// 显示账户状态以及 ChatGPT 和 API Key 登录入口。
  /// Shows account status plus ChatGPT and API-key login entry points.
  Future<void> _showAccount() async {
    final apiKey = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final controller = _controller;
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
                    const Text('请选择主目录；应用会自动连接本地运行时。')
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

  /// 展示由 Codex App Server 原生加载的配置来源，不在应用内收集 Provider 凭据。
  /// Shows the configuration source loaded natively by App Server without collecting provider credentials.
  Future<void> _showCodexConfiguration() async {
    await _controller.refreshCodexConfiguration();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('codex-configuration-dialog'),
        title: const Text('Codex 配置'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '模型、Provider、Base URL 和凭据由本地 Codex App Server 按配置优先级直接读取，本应用不再单独收集或保存这些字段。',
                ),
                const SizedBox(height: 16),
                Text('读取状态', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  _controller.codexConfigurationStatusLabel,
                  key: const Key('codex-configuration-status'),
                ),
                if (_controller.codexConfigurationError case final error?) ...[
                  const SizedBox(height: 4),
                  Text(
                    error,
                    key: const Key('codex-configuration-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text('当前模型', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(
                  _controller.configuredModelLabel,
                  key: const Key('codex-configured-model'),
                ),
                const SizedBox(height: 4),
                Text(
                  '来源：${_controller.configuredModelSourceLabel}',
                  key: const Key('codex-configured-model-source'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  'Provider',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _controller.providerLabel,
                  key: const Key('codex-configured-provider'),
                ),
                const SizedBox(height: 4),
                Text(
                  '来源：${_controller.configuredProviderSourceLabel}',
                  key: const Key('codex-configured-provider-source'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text('用户配置文件', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(
                  _controller.codexUserConfigPath,
                  key: const Key('codex-configuration-path'),
                ),
                const SizedBox(height: 14),
                Text(
                  '“已读取”表示模型和 Provider 已由 Codex 运行时解析；凭据、网络和 Base URL 是否可用，仍需成功创建一次任务才能确认。',
                  key: const Key('codex-configuration-verification-note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '输入框右下角的模型和推理强度选择只影响后续新建任务，不会改写 Codex 配置，也不会覆盖历史任务原有模型。',
                  key: const Key('codex-model-selection-scope-note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 探测并显示 Codex CLI 状态，同时提供路径配置入口。
  /// Probes and shows Codex CLI status while offering path configuration.
  Future<void> _showRuntime() async {
    await _controller.inspectRuntime();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final controller = _controller;
          final probe = controller.runtimeProbe;
          return AlertDialog(
            title: const Text('Codex CLI 运行时'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
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
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '最近运行时日志（${controller.runtimeLogs.length}/200）',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: controller.runtimeLogs.isEmpty
                              ? null
                              : controller.clearRuntimeLogs,
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      key: const Key('runtime-diagnostics-log'),
                      constraints: const BoxConstraints(maxHeight: 180),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          controller.runtimeLogs.isEmpty
                              ? '本次应用运行中尚未记录 stderr 或协议日志。'
                              : controller.runtimeLogs
                                    .map((entry) => entry.toDiagnosticLine())
                                    .join('\n'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '日志只保留在内存中，最多 200 条；展示和复制前都会脱敏。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                key: const Key('copy-runtime-diagnostics-button'),
                onPressed: _copyRuntimeDiagnosticReport,
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: const Text('复制诊断'),
              ),
              TextButton.icon(
                key: const Key('export-runtime-diagnostics-button'),
                onPressed: _exportRuntimeDiagnosticReport,
                icon: const Icon(Icons.save_alt_outlined, size: 18),
                label: const Text('导出诊断'),
              ),
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

  /// 将当前脱敏运行时诊断复制到系统剪贴板，并提示用户可安全分享的范围。
  /// Copies the current redacted runtime diagnostics to the system clipboard and confirms the shareable scope.
  Future<void> _copyRuntimeDiagnosticReport() async {
    await Clipboard.setData(
      ClipboardData(text: _controller.buildRuntimeDiagnosticReport()),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制脱敏运行时诊断。')));
    }
  }

  /// 再次生成脱敏诊断报告并保存为用户选择的本地文本文件。
  /// Rebuilds the redacted diagnostic report and saves it as a user-selected local text file.
  Future<void> _exportRuntimeDiagnosticReport() async {
    final location = await getSaveLocation(
      suggestedName: 'codex-desk-diagnostics.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Text', extensions: ['txt']),
      ],
    );
    if (location == null) return;
    try {
      await File(
        location.path,
      ).writeAsString(_controller.buildRuntimeDiagnosticReport(), flush: true);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已导出脱敏运行时诊断。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出诊断失败：${error.toString()}')));
      }
    }
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
      await _controller.renameThread(thread, nextName);
    }
  }

  /// 确认后归档指定历史线程。
  /// Archives a specified history thread after confirmation.
  Future<void> _archiveThread(CodexThread thread) async {
    await _archiveThreads([thread]);
  }

  /// 二次确认后批量归档历史线程，并返回实际成功归档的任务 ID。
  /// Archives multiple history threads after confirmation and returns the task IDs that actually archived.
  Future<Set<String>> _archiveThreads(List<CodexThread> threads) async {
    if (threads.isEmpty) return const <String>{};
    final count = threads.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(count == 1 ? '归档任务？' : '归档 $count 个任务？'),
        content: Text(
          count == 1
              ? '“${threads.single.title}”将从当前列表隐藏，但可以在后续归档视图中恢复。'
              : '所选任务将从当前列表隐藏，但可以在后续归档视图中恢复。',
        ),
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
    if (confirmed != true) return const <String>{};
    return _controller.archiveThreads(threads);
  }

  /// 二次确认后永久删除任务及 App Server 定义的派生任务，删除无法恢复。
  /// Permanently deletes a task and App Server-defined descendants after confirmation; deletion cannot be undone.
  Future<void> _deleteThread(CodexThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除任务？'),
        content: Text(
          '“${thread.title}”及其派生任务会从 Codex 中永久删除，无法恢复。本应用的对应本地缓存引用也会移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.deleteThread(thread);
  }

  /// 刷新并显示归档线程，允许用户恢复线程。
  /// Refreshes and shows archived threads, allowing the user to restore one.
  Future<void> _showArchivedThreads() async {
    await _controller.refreshArchivedThreads();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final controller = _controller;
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
                          !controller.isUnarchivingThread(thread.id) &&
                          !controller.isUpdatingThread(thread.id),
                      restoring: controller.isUnarchivingThread(thread.id),
                      onRestore: () => controller.unarchiveThread(thread),
                      onDelete: () => _deleteThread(thread),
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
        animation: _controller,
        builder: (context, _) => AlertDialog(
          title: const Text('文件变更'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: _FileChangesList(
              changes: _controller.fileChanges,
              turnDiff: _controller.turnDiff,
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

  /// 打开当前任务的代码审查视图；审查只读，不会提交或推送仓库。
  /// Opens the current task's read-only code-review surface without committing or pushing.
  Future<void> _showCodeReview() async {
    await _controller.ensureFileChangeDiffs();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _CodeReviewDialog(
          changes: _controller.fileChanges,
          turnDiff: _controller.turnDiff,
        ),
      ),
    );
  }

  /// 刷新并展示当前项目的只读 Git 状态和文件 Diff，不提供仓库写操作。
  /// Refreshes and shows the current project's read-only Git status and file diffs without repository write actions.
  Future<void> _showGitProject() async {
    await _controller.refreshGitProject();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _GitProjectDialog(controller: _controller),
    );
  }

  /// 刷新并显示插件管理器，支持本地 marketplace 与启用状态。
  /// Refreshes and shows the plugin manager for local marketplaces and states.
  Future<void> _showPlugins() async {
    await _controller.refreshPlugins();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final controller = _controller;
          final palette = YeknomPalette.of(context);
          return AlertDialog(
            key: const Key('plugin-manager-dialog'),
            title: const Text('Codex 插件'),
            content: SizedBox(
              width: 640,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('插件由本机 Codex CLI 管理；安装或启停后，应用会自动重连并用于后续新任务。'),
                  const SizedBox(height: 12),
                  if (controller.pluginsLoading || controller.pluginSaving)
                    const LinearProgressIndicator(),
                  if (controller.pluginActionProgress case final progress?) ...[
                    const SizedBox(height: 10),
                    Row(
                      key: const Key('plugin-action-progress'),
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(progress)),
                      ],
                    ),
                  ],
                  if (controller.pluginsError case final error?) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      key: const Key('plugin-action-error'),
                      style: TextStyle(color: palette.fault),
                    ),
                  ],
                  if (controller.pluginActionResult case final result?) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const Key('plugin-action-result'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: palette.ack.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.ack),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.restart_alt, size: 19),
                          const SizedBox(width: 8),
                          Expanded(child: Text(result)),
                        ],
                      ),
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
                                active:
                                    controller.pluginActionTargetId ==
                                    plugin.id,
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
      await _controller.addPluginMarketplace(selected!);
    }
  }

  /// 刷新并显示已配置 marketplace，支持 Git 更新与移除。
  /// Refreshes and shows configured marketplaces with Git updates and removal.
  Future<void> _showMarketplaces() async {
    await _controller.refreshMarketplaces();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final controller = _controller;
          final error = controller.marketplacesError;
          return AlertDialog(
            title: const Text('插件市场'),
            content: SizedBox(
              width: 640,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.pluginSaving) const LinearProgressIndicator(),
                  if (controller.pluginActionProgress case final progress?) ...[
                    const SizedBox(height: 10),
                    Text(
                      progress,
                      key: const Key('marketplace-action-progress'),
                    ),
                  ],
                  if (controller.pluginsError case final actionError?) ...[
                    const SizedBox(height: 10),
                    Text(
                      actionError,
                      style: TextStyle(color: YeknomPalette.of(context).fault),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: controller.marketplacesLoading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                        ? Center(child: Text(error))
                        : controller.marketplaces.isEmpty
                        ? const Center(child: Text('尚未配置插件市场。'))
                        : ListView.separated(
                            itemCount: controller.marketplaces.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final marketplace =
                                  controller.marketplaces[index];
                              return _MarketplaceTile(
                                marketplace: marketplace,
                                busy: controller.pluginSaving,
                                onUpgrade: () => controller
                                    .upgradePluginMarketplace(marketplace.name),
                                onRemove: () => _removeMarketplace(marketplace),
                              );
                            },
                          ),
                  ),
                ],
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
      await _controller.removePluginMarketplace(marketplace);
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
    if (confirmed == true) await _controller.removePlugin(plugin);
  }

  /// 构建响应控制器状态的工作区主布局。
  /// Builds the main workspace layout in response to controller state.
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? ref.watch(codexControllerProvider)!;
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
              onChooseWorkspace: _showWorkspaceDirectories,
              onAccount: _showAccount,
              onCodexConfiguration: _showCodexConfiguration,
              onPlugins: _showPlugins,
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
                        onChooseWorkspace: _showWorkspaceDirectories,
                        onCreateWorkspace: () => unawaited(_createWorkspace()),
                        onConfigureRuntime: _showRuntime,
                        onRenameThread: _renameThread,
                        onArchiveThread: _archiveThread,
                        onArchiveThreads: _archiveThreads,
                        onDeleteThread: _deleteThread,
                        onShowArchivedThreads: _showArchivedThreads,
                        onExportHistory: _exportConversationHistory,
                        onImportHistory: _importConversationHistory,
                        onShowGitProject: _showGitProject,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _ConversationPane(
                          controller: controller,
                          composer: _composer,
                          timelineScrollController: _timelineScrollController,
                          onSend: _send,
                          onSteer: _steer,
                          onAdjustDirection: _adjustDirection,
                          onShowFileChanges: _showFileChanges,
                          onReview: _showCodeReview,
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
  }
}

/// 展示一个主目录或附加目录，并在窄窗口中安全截断路径。
/// Displays a primary or additional directory while safely truncating its path in narrow windows.
class _WorkspaceDirectoryTile extends StatelessWidget {
  const _WorkspaceDirectoryTile({
    required this.path,
    required this.label,
    required this.description,
    this.primary = false,
    this.trailing,
    super.key,
  });

  final String? path;
  final String label;
  final String description;
  final bool primary;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final visiblePath = path ?? label;
    return Container(
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: ListTile(
        leading: Icon(
          primary ? Icons.folder_special_outlined : Icons.folder_outlined,
        ),
        title: Tooltip(
          message: path ?? '',
          child: Text(
            visiblePath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('$label · $description'),
        ),
        trailing: trailing,
      ),
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
    required this.onAccount,
    required this.onCodexConfiguration,
    required this.onPlugins,
  });

  final CodexController controller;
  final ThemeMode themeMode;
  final YeknomColorPreset themePreset;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<YeknomColorPreset>? onThemePresetChanged;
  final VoidCallback onChooseWorkspace;
  final Future<void> Function() onAccount;
  final Future<void> Function() onCodexConfiguration;
  final Future<void> Function() onPlugins;

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
      RuntimeStatus.stopped =>
        controller.workspacePath == null ? '等待目录' : '等待连接',
      RuntimeStatus.starting => '连接中',
      RuntimeStatus.ready => '已就绪',
      RuntimeStatus.running => '执行中',
      RuntimeStatus.failed => '连接失败',
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
                        key: ValueKey('theme-preset-${action.preset!.name}'),
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
                key: const Key('codex-configuration-button'),
                tooltip: 'Provider：${controller.providerLabel}',
                onPressed: onCodexConfiguration,
                icon: const Icon(Icons.route_outlined),
              )
            else
              TextButton.icon(
                key: const Key('codex-configuration-button'),
                onPressed: onCodexConfiguration,
                icon: const Icon(Icons.route_outlined),
                label: Text(controller.providerLabel),
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
                tooltip: '管理工作区',
                onPressed: onChooseWorkspace,
                icon: const Icon(Icons.folder_copy_outlined),
              )
            else
              TextButton.icon(
                onPressed: onChooseWorkspace,
                icon: const Icon(Icons.folder_copy_outlined),
                label: const Text('工作区'),
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
    required this.active,
    required this.onEnabledChanged,
    required this.onInstall,
    required this.onRemove,
  });

  final CodexPlugin plugin;
  final bool busy;
  final bool active;
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
      trailing: active
          ? const SizedBox(
              key: Key('plugin-tile-progress'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : plugin.installed
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

/// 在侧栏中以紧凑仓库条目展示一个可切换工作区。
/// Displays one switchable workspace as a compact repository-style sidebar entry.
class _SidebarWorkspaceTile extends StatelessWidget {
  const _SidebarWorkspaceTile({
    required this.workspace,
    required this.active,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final WorkspaceConfiguration workspace;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  /// 从主目录路径提取适合侧栏识别的工作区名称。
  /// Extracts a recognizable sidebar name from the primary-directory path.
  String get _displayName {
    final normalized = workspace.primaryPath.endsWith(Platform.pathSeparator)
        ? workspace.primaryPath.substring(0, workspace.primaryPath.length - 1)
        : workspace.primaryPath;
    final separator = normalized.lastIndexOf(Platform.pathSeparator);
    return separator < 0 ? normalized : normalized.substring(separator + 1);
  }

  /// 构建选中状态轨、工作区名称、完整路径和附加目录数量。
  /// Builds the selection rail, workspace name, full path, and additional-root count.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      selected: active,
      button: !active,
      label: active ? '当前工作区 $_displayName' : '切换到工作区 $_displayName',
      child: InkWell(
        onTap: active || !enabled ? null : onTap,
        child: ColoredBox(
          color: active ? palette.selected : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 3,
                height: 52,
                color: active ? palette.active : Colors.transparent,
              ),
              const SizedBox(width: 9),
              Icon(
                active ? Icons.folder_special_outlined : Icons.folder_outlined,
                size: 18,
                color: active ? palette.active : palette.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                            ),
                          ),
                          if (workspace.additionalPaths.isNotEmpty)
                            Text(
                              '+${workspace.additionalPaths.length}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: palette.muted),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Tooltip(
                        message: workspace.primaryPath,
                        child: Text(
                          workspace.primaryPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: palette.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.controller,
    required this.onChooseWorkspace,
    required this.onCreateWorkspace,
    required this.onConfigureRuntime,
    required this.onRenameThread,
    required this.onArchiveThread,
    required this.onArchiveThreads,
    required this.onDeleteThread,
    required this.onShowArchivedThreads,
    required this.onExportHistory,
    required this.onImportHistory,
    required this.onShowGitProject,
  });

  final CodexController controller;
  final VoidCallback onChooseWorkspace;
  final VoidCallback onCreateWorkspace;
  final Future<void> Function() onConfigureRuntime;
  final Future<void> Function(CodexThread thread) onRenameThread;
  final Future<void> Function(CodexThread thread) onArchiveThread;
  final Future<Set<String>> Function(List<CodexThread> threads)
  onArchiveThreads;
  final Future<void> Function(CodexThread thread) onDeleteThread;
  final Future<void> Function() onShowArchivedThreads;
  final Future<void> Function() onExportHistory;
  final Future<void> Function() onImportHistory;
  final Future<void> Function() onShowGitProject;

  /// 创建管理侧栏搜索状态的 State 对象。
  /// Creates the State object that manages sidebar search state.
  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final TextEditingController _threadSearch = TextEditingController();
  String _query = '';
  bool _batchMode = false;
  final Set<String> _selectedThreadIds = {};

  /// 释放任务搜索输入控制器。
  /// Disposes the task-search text controller.
  @override
  void dispose() {
    _threadSearch.dispose();
    super.dispose();
  }

  /// 将当前选中的活跃任务提交给带二次确认的批量归档操作。
  /// Sends selected active tasks to the confirmation-backed bulk archive action.
  Future<void> _archiveSelectedThreads(CodexController controller) async {
    final selected = controller.threads
        .where((thread) => _selectedThreadIds.contains(thread.id))
        .toList(growable: false);
    final archivedIds = await widget.onArchiveThreads(selected);
    if (!mounted) return;
    setState(() {
      _selectedThreadIds.removeAll(archivedIds);
      if (_selectedThreadIds.isEmpty && archivedIds.isNotEmpty) {
        _batchMode = false;
      }
    });
  }

  /// 构建工作区选择、线程历史和 CLI 配置侧栏。
  /// Builds the sidebar for workspace selection, thread history, and CLI setup.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final controller = widget.controller;
    final query = _query.trim().toLowerCase();
    final filteredThreads = controller.threads
        .where(
          (thread) =>
              query.isEmpty ||
              thread.title.toLowerCase().contains(query) ||
              thread.preview.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final visibleThreads = [
      ...filteredThreads.where(
        (thread) => controller.isThreadPinned(thread.id),
      ),
      ...filteredThreads.where(
        (thread) => !controller.isThreadPinned(thread.id),
      ),
    ];
    // 保持用户创建工作区时的顺序；切换只改变选中态，不重排列表。
    // Preserve creation order; switching changes selection without reordering the list.
    final workspaces = controller.workspaceConfigurations;
    return SizedBox(
      width: 250,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('工作区', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                IconButton(
                  key: const Key('sidebar-create-workspace-button'),
                  tooltip: '新建工作区',
                  visualDensity: VisualDensity.compact,
                  onPressed: controller.canChangePrimaryWorkspace
                      ? widget.onCreateWorkspace
                      : null,
                  icon: const Icon(Icons.add, size: 19),
                ),
                IconButton(
                  key: const Key('sidebar-manage-workspaces-button'),
                  tooltip: '管理工作区',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onChooseWorkspace,
                  icon: const Icon(Icons.tune, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Ink(
              key: const Key('workspace-picker-surface'),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: workspaces.isEmpty
                    ? InkWell(
                        key: const Key('sidebar-workspace-empty'),
                        onTap: controller.canChangePrimaryWorkspace
                            ? widget.onCreateWorkspace
                            : null,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.create_new_folder_outlined, size: 19),
                              SizedBox(width: 9),
                              Expanded(child: Text('新建第一个工作区')),
                            ],
                          ),
                        ),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 168),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: workspaces.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: palette.border),
                          itemBuilder: (context, index) {
                            final workspace = workspaces[index];
                            final active =
                                workspace.primaryPath ==
                                controller.workspacePath;
                            return _SidebarWorkspaceTile(
                              key: ValueKey(
                                'sidebar-workspace-${workspace.primaryPath}',
                              ),
                              workspace: workspace,
                              active: active,
                              enabled: controller.canChangePrimaryWorkspace,
                              onTap: () => unawaited(
                                controller.selectWorkspaceAndReconnect(
                                  workspace.primaryPath,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
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
                PopupMenuButton<_HistoryAction>(
                  tooltip: '本地历史',
                  enabled: controller.workspacePath != null,
                  icon: const Icon(Icons.inventory_2_outlined, size: 20),
                  onSelected: (action) async {
                    switch (action) {
                      case _HistoryAction.archived:
                        await widget.onShowArchivedThreads();
                      case _HistoryAction.batchArchive:
                        setState(() => _batchMode = true);
                      case _HistoryAction.export:
                        await widget.onExportHistory();
                      case _HistoryAction.import:
                        await widget.onImportHistory();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _HistoryAction.archived,
                      child: ListTile(
                        leading: Icon(Icons.inventory_2_outlined),
                        title: Text('已归档任务'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HistoryAction.batchArchive,
                      child: ListTile(
                        leading: Icon(Icons.checklist_outlined),
                        title: Text('批量归档任务'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HistoryAction.export,
                      child: ListTile(
                        leading: Icon(Icons.file_upload_outlined),
                        title: Text('导出本地历史'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HistoryAction.import,
                      child: ListTile(
                        leading: Icon(Icons.file_download_outlined),
                        title: Text('导入到当前项目'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_batchMode) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('已选 ${_selectedThreadIds.length} 个任务'),
                  TextButton(
                    onPressed: () => setState(() {
                      _batchMode = false;
                      _selectedThreadIds.clear();
                    }),
                    child: const Text('取消'),
                  ),
                  FilledButton.tonal(
                    onPressed:
                        _selectedThreadIds.isEmpty ||
                            controller.status != RuntimeStatus.ready
                        ? null
                        : () => _archiveSelectedThreads(controller),
                    child: const Text('归档已选'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              key: const Key('thread-search-field'),
              controller: _threadSearch,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索任务',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _threadSearch.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (controller.threadsLoading && controller.threads.isEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (controller.threadsLoading && controller.threads.isEmpty)
              const SizedBox(height: 6),
            if (controller.threadsError case final error?)
              _MutedText(error)
            else if (controller.threads.isEmpty)
              const _MutedText('暂无历史任务；发送第一条消息后会创建。')
            else if (visibleThreads.isEmpty)
              const _MutedText('没有匹配的任务。')
            else
              Expanded(
                child: ListView.separated(
                  itemCount: visibleThreads.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final thread = visibleThreads[index];
                    return _HistoryThreadTile(
                      thread: thread,
                      selected: controller.activeThreadId == thread.id,
                      pinned: controller.isThreadPinned(thread.id),
                      enabled:
                          controller.status == RuntimeStatus.ready &&
                          !controller.isUpdatingThread(thread.id),
                      selectionMode: _batchMode,
                      batchSelected: _selectedThreadIds.contains(thread.id),
                      onTap: () {
                        if (_batchMode) {
                          setState(() {
                            if (!_selectedThreadIds.add(thread.id)) {
                              _selectedThreadIds.remove(thread.id);
                            }
                          });
                        } else {
                          controller.resumeThread(thread);
                        }
                      },
                      onRename: () => widget.onRenameThread(thread),
                      onArchive: () => widget.onArchiveThread(thread),
                      onDelete: () => widget.onDeleteThread(thread),
                      onTogglePin: () => controller.toggleThreadPinned(thread),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onConfigureRuntime,
              icon: const Icon(Icons.memory_outlined, size: 18),
              label: const Text('Codex CLI'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.workspacePath == null
                  ? null
                  : widget.onShowGitProject,
              icon: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('Git 项目'),
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
    required this.onSteer,
    required this.onAdjustDirection,
    required this.onShowFileChanges,
    required this.onReview,
  });

  final CodexController controller;
  final TextEditingController composer;
  final ScrollController timelineScrollController;
  final Future<bool> Function(_ComposerSubmission submission) onSend;
  final Future<bool> Function(String prompt) onSteer;
  final Future<void> Function(String originalPrompt) onAdjustDirection;
  final Future<void> Function() onShowFileChanges;
  final Future<void> Function() onReview;

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final plan = controller.status == RuntimeStatus.running
                  ? controller.activeTaskPlan
                  : null;
              final planHeight = (constraints.maxHeight - 16).clamp(
                100.0,
                340.0,
              );
              final latestUserIndex = controller.entries.lastIndexWhere(
                (entry) => entry.kind == TimelineKind.user,
              );
              return Stack(
                children: [
                  ListView.separated(
                    controller: timelineScrollController,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      12,
                      24,
                      plan == null ? 12 : planHeight + 28,
                    ),
                    itemCount:
                        controller.entries.length +
                        (controller.status != RuntimeStatus.running &&
                                controller.fileChanges.isNotEmpty
                            ? 1
                            : 0),
                    separatorBuilder: (_, _) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1),
                    ),
                    itemBuilder: (context, index) {
                      if (index == controller.entries.length) {
                        return _FileChangeSummaryCard(
                          changes: controller.fileChanges,
                          turnDiff: controller.turnDiff,
                          onReview: onReview,
                        );
                      }
                      final entry = controller.entries[index];
                      return _TimelineEntry(
                        entry,
                        onAdjustDirection:
                            controller.canSteer &&
                                index == latestUserIndex &&
                                entry.kind == TimelineKind.user
                            ? () => onAdjustDirection(entry.detail)
                            : null,
                      );
                    },
                  ),
                  if (plan != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 620,
                            maxHeight: planHeight,
                          ),
                          child: _TaskPlanPanel(plan: plan),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        _ComposerPanel(
          controller: controller,
          composer: composer,
          onSend: onSend,
          onSteer: onSteer,
        ),
      ],
    );
  }
}

class _DiffStats {
  const _DiffStats(this.additions, this.deletions);

  final int additions;
  final int deletions;

  _DiffStats operator +(_DiffStats other) =>
      _DiffStats(additions + other.additions, deletions + other.deletions);
}

_DiffStats _diffStats(String diff) {
  var additions = 0;
  var deletions = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+++') || line.startsWith('---')) continue;
    if (line.startsWith('+')) additions++;
    if (line.startsWith('-')) deletions++;
  }
  return _DiffStats(additions, deletions);
}

String _diffCountLabel(String prefix, int count, {required bool unknown}) =>
    unknown ? '$prefix?' : '$prefix$count';

class _FileChangeSummaryCard extends StatefulWidget {
  const _FileChangeSummaryCard({
    required this.changes,
    required this.turnDiff,
    required this.onReview,
  });

  final List<CodexFileChange> changes;
  final String? turnDiff;
  final Future<void> Function() onReview;

  @override
  State<_FileChangeSummaryCard> createState() => _FileChangeSummaryCardState();
}

class _FileChangeSummaryCardState extends State<_FileChangeSummaryCard> {
  bool _expanded = false;

  _DiffStats get _stats {
    final stats = widget.changes.fold(
      const _DiffStats(0, 0),
      (total, change) => total + _diffStats(change.diff),
    );
    final fallback = widget.turnDiff;
    final hasMissingDiff = widget.changes.any(
      (change) => change.diff.trim().isEmpty,
    );
    return hasMissingDiff && fallback != null && fallback.isNotEmpty
        ? _diffStats(fallback)
        : stats;
  }

  bool get _statsUnknown =>
      widget.changes.any((change) => change.diff.trim().isEmpty) &&
      (widget.turnDiff == null || widget.turnDiff!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _stats;
    final visibleChanges = _expanded
        ? widget.changes
        : widget.changes.take(3).toList(growable: false);
    final hiddenCount = widget.changes.length - visibleChanges.length;
    return Container(
      key: const Key('file-change-summary-card'),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.field,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.edit_note_outlined, color: palette.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已编辑 ${widget.changes.length} 个文件',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _diffCountLabel(
                                '+',
                                stats.additions,
                                unknown: _statsUnknown,
                              ),
                              style: TextStyle(color: palette.ack),
                            ),
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: _diffCountLabel(
                                '-',
                                stats.deletions,
                                unknown: _statsUnknown,
                              ),
                              style: TextStyle(color: palette.fault),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  key: const Key('review-file-changes-button'),
                  onPressed: () => unawaited(widget.onReview()),
                  child: const Text('审核'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          for (final change in visibleChanges)
            _FileChangeSummaryRow(
              change: change,
              fallbackDiff: widget.changes.length == 1 ? widget.turnDiff : null,
            ),
          if (hiddenCount > 0 || _expanded && widget.changes.length > 3)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Text(
                      _expanded ? '收起文件' : '再显示 $hiddenCount 个文件',
                      style: TextStyle(color: palette.muted),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: palette.muted,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileChangeSummaryRow extends StatefulWidget {
  const _FileChangeSummaryRow({required this.change, this.fallbackDiff});

  final CodexFileChange change;
  final String? fallbackDiff;

  @override
  State<_FileChangeSummaryRow> createState() => _FileChangeSummaryRowState();
}

class _FileChangeSummaryRowState extends State<_FileChangeSummaryRow> {
  static const _previewMargin = 12.0;
  static const _previewGap = 8.0;
  static const _previewMaxWidth = 560.0;
  static const _previewMaxHeight = 330.0;

  final LayerLink _layerLink = LayerLink();
  final ValueNotifier<int> _previewVersion = ValueNotifier(0);
  OverlayEntry? _previewEntry;
  Timer? _hideTimer;
  bool _hovering = false;
  Offset _previewOffset = Offset.zero;
  Alignment _targetAnchor = Alignment.topLeft;
  Alignment _followerAnchor = Alignment.bottomLeft;
  double _previewWidth = _previewMaxWidth;
  double _previewMaxHeightValue = _previewMaxHeight;
  double _previewHeight = _previewMaxHeight;
  bool _previewRefreshScheduled = false;

  String get _diff => widget.change.diff.trim().isEmpty
      ? (widget.fallbackDiff ?? '')
      : widget.change.diff;

  bool _updatePreviewGeometry() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return false;
    final viewport = MediaQuery.sizeOf(context);
    final targetTopLeft = renderObject.localToGlobal(Offset.zero);
    final targetBottom = targetTopLeft.dy + renderObject.size.height;
    final availableAbove = targetTopLeft.dy - _previewMargin - _previewGap;
    final availableBelow =
        viewport.height - targetBottom - _previewMargin - _previewGap;
    final showAbove = availableAbove >= availableBelow;
    final availableHeight = showAbove ? availableAbove : availableBelow;
    final width = (viewport.width - _previewMargin * 2)
        .clamp(1.0, _previewMaxWidth)
        .toDouble();
    final horizontalShift =
        targetTopLeft.dx + width > viewport.width - _previewMargin
        ? viewport.width - _previewMargin - targetTopLeft.dx - width
        : targetTopLeft.dx < _previewMargin
        ? _previewMargin - targetTopLeft.dx
        : 0.0;
    _previewWidth = width;
    _previewMaxHeightValue = availableHeight
        .clamp(1.0, _previewMaxHeight)
        .toDouble();
    final previewLineCount = _previewLines(_diff).length;
    final estimatedHeight = _diff.trim().isEmpty
        ? 96.0
        : 60.0 +
              (previewLineCount > 12 ? 12 : previewLineCount) * 18.0 +
              (previewLineCount > 12 ? 24.0 : 0.0);
    _previewHeight = estimatedHeight < _previewMaxHeightValue
        ? estimatedHeight
        : _previewMaxHeightValue;
    _previewOffset = Offset(
      horizontalShift,
      showAbove
          ? -_previewHeight - _previewGap
          : renderObject.size.height + _previewGap,
    );
    _targetAnchor = Alignment.topLeft;
    _followerAnchor = Alignment.topLeft;
    return true;
  }

  void _showPreview() {
    _hideTimer?.cancel();
    if (_previewEntry != null || !mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || !_updatePreviewGeometry()) return;

    final entry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<int>(
        valueListenable: _previewVersion,
        builder: (context, _, _) => CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: _targetAnchor,
          followerAnchor: _followerAnchor,
          offset: _previewOffset,
          child: IgnorePointer(
            child: UnconstrainedBox(
              alignment: Alignment.topLeft,
              child: _FileChangeHoverPreview(
                path: widget.change.path,
                diff: _diff,
                width: _previewWidth,
                maxHeight: _previewMaxHeightValue,
                height: _previewHeight,
              ),
            ),
          ),
        ),
      ),
    );
    _previewEntry = entry;
    overlay.insert(entry);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      _previewEntry?.remove();
      _previewEntry = null;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _previewEntry?.remove();
    _previewVersion.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _FileChangeSummaryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.change.path != widget.change.path ||
        oldWidget.change.diff != widget.change.diff ||
        oldWidget.fallbackDiff != widget.fallbackDiff) {
      if (_previewEntry != null && !_previewRefreshScheduled) {
        _previewRefreshScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _previewRefreshScheduled = false;
          if (mounted && _previewEntry != null) {
            _updatePreviewGeometry();
            _previewVersion.value++;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _diffStats(_diff);
    final unknown = _diff.trim().isEmpty;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        key: ValueKey('file-change-row-${widget.change.path}'),
        onEnter: (_) {
          setState(() => _hovering = true);
          _showPreview();
        },
        onExit: (_) {
          setState(() => _hovering = false);
          _scheduleHide();
        },
        cursor: SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: palette.field.withValues(alpha: _hovering ? 0.68 : 0.42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.change.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.trace),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _diffCountLabel('+', stats.additions, unknown: unknown),
                style: TextStyle(color: palette.ack),
              ),
              const SizedBox(width: 10),
              Text(
                _diffCountLabel('-', stats.deletions, unknown: unknown),
                style: TextStyle(color: palette.fault),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffPreviewLine {
  const _DiffPreviewLine(this.text, this.lineNumber);

  final String text;
  final int? lineNumber;
}

List<_DiffPreviewLine> _previewLines(String diff) {
  final hunkPattern = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
  var inHunk = false;
  var oldLine = 0;
  var newLine = 0;
  return diff
      .split('\n')
      .map((line) {
        final hunk = hunkPattern.firstMatch(line);
        if (hunk != null) {
          inHunk = true;
          oldLine = int.parse(hunk.group(1)!);
          newLine = int.parse(hunk.group(2)!);
          return _DiffPreviewLine(line, null);
        }
        if (!inHunk) return _DiffPreviewLine(line, null);

        if (line.startsWith('+') && !line.startsWith('+++')) {
          return _DiffPreviewLine(line, newLine++);
        }
        if (line.startsWith('-') && !line.startsWith('---')) {
          return _DiffPreviewLine(line, oldLine++);
        }
        if (line.startsWith(' ')) {
          final number = newLine++;
          oldLine++;
          return _DiffPreviewLine(line, number);
        }
        return _DiffPreviewLine(line, null);
      })
      .toList(growable: false);
}

class _FileChangeHoverPreview extends StatelessWidget {
  const _FileChangeHoverPreview({
    required this.path,
    required this.diff,
    required this.width,
    required this.maxHeight,
    required this.height,
  });

  final String path;
  final String diff;
  final double width;
  final double maxHeight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _diffStats(diff);
    final lines = _previewLines(diff);
    final visibleLines = lines.length > 12 ? lines.take(12).toList() : lines;
    final truncated = visibleLines.length < lines.length;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('file-change-hover-preview'),
        width: width,
        height: height,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 17,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.trace,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '+${stats.additions}',
                    style: TextStyle(color: palette.ack),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-${stats.deletions}',
                    style: TextStyle(color: palette.fault),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            if (diff.trim().isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: _MutedText('App Server 未提供可显示的 Diff。'),
              )
            else
              Flexible(
                child: Container(
                  color: palette.field,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText.rich(
                        TextSpan(
                          children: _previewSpans(palette, visibleLines),
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Text(
                  '仅显示前 12 行 · 打开“审核”查看完整 Diff',
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _previewSpans(
    YeknomPalette palette,
    List<_DiffPreviewLine> lines,
  ) {
    return [
      for (var index = 0; index < lines.length; index++)
        TextSpan(
          text:
              '${lines[index].lineNumber?.toString().padLeft(4) ?? '    '}  '
              '${lines[index].text}\n',
          style: TextStyle(
            color: _lineColor(palette, lines[index].text),
            backgroundColor: _lineBackground(palette, lines[index].text),
          ),
        ),
    ];
  }

  Color _lineColor(YeknomPalette palette, String line) {
    return switch (line) {
      _ when line.startsWith('+++') || line.startsWith('---') => palette.muted,
      _ when line.startsWith('+') => palette.ack,
      _ when line.startsWith('-') => palette.fault,
      _ when line.startsWith('@@') => palette.active,
      _ => palette.trace,
    };
  }

  Color? _lineBackground(YeknomPalette palette, String line) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return palette.ack.withValues(alpha: 0.12);
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return palette.fault.withValues(alpha: 0.12);
    }
    return null;
  }
}

class _CodeReviewDialog extends StatefulWidget {
  const _CodeReviewDialog({required this.changes, required this.turnDiff});

  final List<CodexFileChange> changes;
  final String? turnDiff;

  @override
  State<_CodeReviewDialog> createState() => _CodeReviewDialogState();
}

class _CodeReviewDialogState extends State<_CodeReviewDialog> {
  int _selectedIndex = 0;

  List<CodexFileChange> get _targets {
    if (widget.changes.isNotEmpty) {
      final fallback = widget.turnDiff;
      final hasMissingDiff = widget.changes.any(
        (change) => change.diff.trim().isEmpty,
      );
      if (hasMissingDiff && fallback != null && fallback.isNotEmpty) {
        return [
          ...widget.changes,
          CodexFileChange(path: '本次任务完整 Diff', kind: '任务', diff: fallback),
        ];
      }
      return widget.changes;
    }
    final diff = widget.turnDiff;
    if (diff == null || diff.isEmpty) return const [];
    return [CodexFileChange(path: '本次任务完整 Diff', kind: '任务', diff: diff)];
  }

  _DiffStats get _stats {
    final fallback = widget.turnDiff;
    final hasMissingDiff = widget.changes.any(
      (change) => change.diff.trim().isEmpty,
    );
    if (hasMissingDiff && fallback != null && fallback.isNotEmpty) {
      return _diffStats(fallback);
    }
    return _targets.fold(
      const _DiffStats(0, 0),
      (total, change) => total + _diffStats(change.diff),
    );
  }

  bool get _statsUnknown =>
      widget.changes.any((change) => change.diff.trim().isEmpty) &&
      (widget.turnDiff == null || widget.turnDiff!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final targets = _targets;
    final selected = targets.isEmpty
        ? null
        : targets[_selectedIndex.clamp(0, targets.length - 1)];
    final stats = _stats;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('code-review-dialog'),
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: palette.bench,
      child: SizedBox(
        width: (size.width - 24).clamp(680.0, 1240.0).toDouble(),
        height: (size.height - 24).clamp(480.0, 820.0).toDouble(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              child: Row(
                children: [
                  Icon(Icons.edit_note_outlined, color: palette.muted),
                  const SizedBox(width: 10),
                  Text('审查', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭审查',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  _ReviewFilter(label: '所有仓库', icon: Icons.expand_more),
                  const SizedBox(width: 18),
                  _ReviewFilter(label: '上一轮', icon: Icons.expand_more),
                  const SizedBox(width: 18),
                  Text(
                    _diffCountLabel(
                      '+',
                      stats.additions,
                      unknown: _statsUnknown,
                    ),
                    style: TextStyle(color: palette.ack),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _diffCountLabel(
                      '-',
                      stats.deletions,
                      unknown: _statsUnknown,
                    ),
                    style: TextStyle(color: palette.fault),
                  ),
                  const Spacer(),
                  Text(
                    widget.changes.isEmpty
                        ? '完整 Diff'
                        : '${widget.changes.length} 个文件',
                    style: TextStyle(color: palette.muted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            Expanded(
              child: targets.isEmpty
                  ? const Center(child: Text('当前任务没有可审查的文件变更。'))
                  : Row(
                      children: [
                        SizedBox(
                          width: 320,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: targets.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: palette.border),
                            itemBuilder: (context, index) {
                              final target = targets[index];
                              final targetStats = _diffStats(target.diff);
                              return ListTile(
                                selected: index == _selectedIndex,
                                selectedTileColor: palette.selected,
                                dense: true,
                                leading: Icon(
                                  Icons.description_outlined,
                                  size: 18,
                                  color: index == _selectedIndex
                                      ? palette.ack
                                      : palette.muted,
                                ),
                                title: Text(
                                  target.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  target.diff.trim().isEmpty
                                      ? 'Diff unavailable'
                                      : '${targetStats.additions} additions · ${targetStats.deletions} deletions',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () =>
                                    setState(() => _selectedIndex = index),
                              );
                            },
                          ),
                        ),
                        VerticalDivider(width: 1, color: palette.border),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: selected == null
                                ? const SizedBox.shrink()
                                : _ReviewDiffViewer(change: selected),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewFilter extends StatelessWidget {
  const _ReviewFilter({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: palette.trace)),
        const SizedBox(width: 4),
        Icon(icon, size: 18, color: palette.muted),
      ],
    );
  }
}

class _ReviewDiffViewer extends StatelessWidget {
  const _ReviewDiffViewer({required this.change});

  final CodexFileChange change;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _diffStats(change.diff);
    final unknown = change.diff.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: palette.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                change.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              _diffCountLabel('+', stats.additions, unknown: unknown),
              style: TextStyle(color: palette.ack),
            ),
            const SizedBox(width: 8),
            Text(
              _diffCountLabel('-', stats.deletions, unknown: unknown),
              style: TextStyle(color: palette.fault),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: change.diff.isEmpty
                ? const Center(child: Text('没有可显示的 Diff。'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText.rich(
                        TextSpan(children: _diffSpans(palette, change.diff)),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

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

class _TaskPlanPanel extends StatefulWidget {
  const _TaskPlanPanel({required this.plan});

  final TaskPlan plan;

  /// 创建负责当前步骤自动聚焦的面板状态。
  /// Creates panel state that automatically focuses the current step.
  @override
  State<_TaskPlanPanel> createState() => _TaskPlanPanelState();
}

class _TaskPlanPanelState extends State<_TaskPlanPanel> {
  late List<GlobalKey> _stepKeys;

  TaskPlan get plan => widget.plan;

  /// 初始化步骤锚点，并在首帧把当前步骤滚入可见区域。
  /// Initializes step anchors and scrolls the current step into view after the first frame.
  @override
  void initState() {
    super.initState();
    _stepKeys = List.generate(plan.steps.length, (_) => GlobalKey());
    _scheduleFocusedStepVisibility();
  }

  /// 在计划长度或当前步骤变化后同步锚点并重新聚焦。
  /// Synchronizes anchors and refocuses after the plan length or current step changes.
  @override
  void didUpdateWidget(covariant _TaskPlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_stepKeys.length != plan.steps.length) {
      _stepKeys = List.generate(plan.steps.length, (_) => GlobalKey());
    }
    if (oldWidget.plan.focusedStepIndex != plan.focusedStepIndex ||
        oldWidget.plan.steps.length != plan.steps.length) {
      _scheduleFocusedStepVisibility();
    }
  }

  /// 等待布局完成后，将当前步骤平滑滚动到步骤列表的中央可见区域。
  /// Waits for layout, then smoothly scrolls the current step into the center of the visible list.
  void _scheduleFocusedStepVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = plan.focusedStepIndex;
      if (index < 0 || index >= _stepKeys.length) return;
      final stepContext = _stepKeys[index].currentContext;
      if (stepContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          stepContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// 构建运行中任务的悬浮分步进度面板与当前步骤指示。
  /// Builds the floating step-progress panel and current-step indicator for a running task.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final focusedIndex = plan.focusedStepIndex;
    final currentStep = focusedIndex < 0 ? 0 : focusedIndex + 1;
    return Semantics(
      container: true,
      label: '执行计划，共 ${plan.steps.length} 步，当前第 $currentStep 步',
      child: Column(
        key: const Key('task-plan-progress'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 17,
                          color: palette.active,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            plan.explanation ?? '执行计划',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: palette.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${plan.completedStepCount}/${plan.steps.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: palette.border),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          plan.steps.length,
                          (index) => KeyedSubtree(
                            key: _stepKeys[index],
                            child: _TaskPlanStepRow(
                              key: Key('task-plan-step-$index'),
                              step: plan.steps[index],
                              focused: index == focusedIndex,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('task-plan-current-step'),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TaskPlanStatusMark(
                  status: focusedIndex < 0
                      ? TaskPlanStepStatus.pending
                      : plan.steps[focusedIndex].status,
                  active: true,
                ),
                const SizedBox(width: 7),
                Text(
                  '第 $currentStep / ${plan.steps.length} 步',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPlanStepRow extends StatelessWidget {
  const _TaskPlanStepRow({
    required this.step,
    required this.focused,
    super.key,
  });

  final TaskPlanStep step;
  final bool focused;

  /// 构建单条计划步骤，并以文字语义和图形共同表达状态。
  /// Builds one plan step, expressing status through both semantics and visuals.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final statusLabel = switch (step.status) {
      TaskPlanStepStatus.pending => '待执行',
      TaskPlanStepStatus.inProgress => '进行中',
      TaskPlanStepStatus.completed => '已完成',
    };
    return Semantics(
      label: '$statusLabel：${step.step}',
      child: Container(
        color: focused
            ? palette.active.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _TaskPlanStatusMark(status: step.status, active: focused),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                step.step,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: step.status == TaskPlanStepStatus.completed
                      ? palette.muted
                      : palette.trace,
                  fontWeight: focused ? FontWeight.w600 : FontWeight.w400,
                  decoration: step.status == TaskPlanStepStatus.completed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskPlanStatusMark extends StatelessWidget {
  const _TaskPlanStatusMark({required this.status, required this.active});

  final TaskPlanStepStatus status;
  final bool active;

  /// 构建静态状态标记，避免持续动画干扰阅读和 Widget 测试稳定性。
  /// Builds a static status mark to avoid perpetual motion and unstable widget tests.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (status == TaskPlanStepStatus.completed) {
      return Icon(Icons.check_circle, size: 16, color: palette.ack);
    }
    final color = active ? palette.active : palette.muted;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: active ? 2 : 1.5),
      ),
      alignment: Alignment.center,
      child: status == TaskPlanStepStatus.inProgress
          ? Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
          : null,
    );
  }
}

/// 输入框右下角的新任务模型与推理强度双拨盘。
/// A paired new-task model and reasoning-effort control in the composer's lower-right corner.
class _ComposerModelControls extends StatelessWidget {
  const _ComposerModelControls({
    required this.controller,
    required this.compact,
  });

  final CodexController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final modelEnabled = controller.canSelectModel;
    final effortEnabled = controller.canSelectReasoningEffort;
    final selectionError = controller.modelSelectionError;
    final contentColor = selectionError != null
        ? palette.fault
        : modelEnabled
        ? palette.trace
        : palette.muted;
    final modelWidth = compact ? 88.0 : 152.0;
    final effortWidth = compact ? 58.0 : 76.0;
    return Container(
      key: const Key('composer-model-controls'),
      height: 34,
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selectionError == null ? palette.controlBorder : palette.fault,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            key: const Key('model-selector'),
            enabled: modelEnabled,
            padding: EdgeInsets.zero,
            tooltip:
                selectionError ?? '切换后续新任务的模型：${controller.selectedModelLabel}',
            onSelected: (value) {
              unawaited(controller.setModel(value.isEmpty ? null : value));
            },
            itemBuilder: (context) => [
              if (selectionError != null)
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(selectionError),
                ),
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('仅影响后续新任务'),
              ),
              CheckedPopupMenuItem(
                key: const Key('model-option-follow-config'),
                value: '',
                checked: controller.selectedModelId == null,
                child: Text('跟随 Codex 配置 · ${controller.configuredModelLabel}'),
              ),
              ...controller.modelOptions.map(
                (option) => CheckedPopupMenuItem(
                  key: ValueKey('model-option-${option.id}'),
                  value: option.id,
                  checked: controller.selectedModelId == option.id,
                  child: Text(
                    '新任务模型：${option.displayName}${option.displayName == option.id ? '' : ' · ${option.id}'}',
                  ),
                ),
              ),
            ],
            child: SizedBox(
              width: modelWidth,
              height: 32,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 5),
                child: Row(
                  children: [
                    Icon(
                      selectionError == null
                          ? Icons.smart_toy_outlined
                          : Icons.error_outline,
                      size: 15,
                      color: contentColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        controller.newTaskModelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: contentColor),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 15, color: palette.muted),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 18, color: palette.controlBorder),
          PopupMenuButton<ReasoningEffort>(
            key: const Key('reasoning-effort-selector'),
            enabled: effortEnabled,
            padding: EdgeInsets.zero,
            tooltip:
                selectionError ??
                '切换后续新任务的推理强度：${controller.reasoningEffort.label}',
            onSelected: (value) {
              unawaited(controller.setReasoningEffort(value));
            },
            itemBuilder: (context) => controller.reasoningEffortOptions
                .map(
                  (effort) => CheckedPopupMenuItem(
                    key: ValueKey('reasoning-option-${effort.name}'),
                    value: effort,
                    checked: controller.reasoningEffort == effort,
                    child: Text('新任务推理强度：${effort.label}'),
                  ),
                )
                .toList(growable: false),
            child: SizedBox(
              width: effortWidth,
              height: 32,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        '推理${controller.reasoningEffort.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: contentColor),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 15, color: palette.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerActivityPill extends StatelessWidget {
  const _ComposerActivityPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      key: const Key('composer-activity-pill'),
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
                color: active ? palette.active : palette.muted,
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ],
      ),
    );
  }
}

class _ComposerFileChangePill extends StatelessWidget {
  const _ComposerFileChangePill({
    required this.changes,
    required this.turnDiff,
  });

  final List<CodexFileChange> changes;
  final String? turnDiff;

  _DiffStats get _stats {
    final stats = changes.fold(
      const _DiffStats(0, 0),
      (total, change) => total + _diffStats(change.diff),
    );
    final fallback = turnDiff;
    final hasMissingDiff = changes.any((change) => change.diff.trim().isEmpty);
    return hasMissingDiff && fallback != null && fallback.isNotEmpty
        ? _diffStats(fallback)
        : stats;
  }

  bool get _statsUnknown =>
      changes.any((change) => change.diff.trim().isEmpty) &&
      (turnDiff == null || turnDiff!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _stats;
    return Container(
      key: const Key('composer-file-change-pill'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${changes.length} 个文件已更改',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
          const SizedBox(width: 9),
          Text(
            _diffCountLabel('+', stats.additions, unknown: _statsUnknown),
            style: TextStyle(color: palette.ack),
          ),
          const SizedBox(width: 8),
          Text(
            _diffCountLabel('-', stats.deletions, unknown: _statsUnknown),
            style: TextStyle(color: palette.fault),
          ),
        ],
      ),
    );
  }
}

class _ComposerPanel extends StatefulWidget {
  const _ComposerPanel({
    required this.controller,
    required this.composer,
    required this.onSend,
    required this.onSteer,
  });

  final CodexController controller;
  final TextEditingController composer;
  final Future<bool> Function(_ComposerSubmission submission) onSend;
  final Future<bool> Function(String prompt) onSteer;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
  static const _clipboardFileReader = ClipboardFileReader();
  final List<_ComposerAttachment> _attachments = [];
  final Set<String> _selectedSkillPaths = {};
  final Map<String, Uint8List> _securityBookmarks = {};
  final Set<String> _temporaryAttachmentPaths = {};
  late RuntimeStatus _lastRuntimeStatus;
  bool _draggingFiles = false;
  bool _includeWorkspace = false;
  bool _planMode = false;
  bool _recordSkill = false;
  String? _goal;

  CodexController get controller => widget.controller;
  TextEditingController get composer => widget.composer;

  int get _fileChangeCount => controller.entries
      .where((entry) => entry.title == '文件变更')
      .fold(0, (total, entry) => total + entry.detail.split('\n').length);

  List<CodexSkill> get _selectedSkills => controller.skills
      .where((skill) => _selectedSkillPaths.contains(skill.path))
      .toList(growable: false);

  bool get _hasComposerContext =>
      _attachments.isNotEmpty ||
      _includeWorkspace ||
      _goal?.isNotEmpty == true ||
      _planMode ||
      _recordSkill ||
      _selectedSkillPaths.isNotEmpty;

  /// 指示运行中的 steering 是否仍有无法随纯文本发送的临时上下文。
  /// Indicates whether steering still has transient context that cannot be sent as plain text.
  bool get _hasUnsupportedSteeringContext =>
      _attachments.isNotEmpty ||
      _includeWorkspace ||
      _recordSkill ||
      _selectedSkillPaths.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _lastRuntimeStatus = controller.status;
    controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _ComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _lastRuntimeStatus = controller.status;
    controller.addListener(_handleControllerChanged);
    _releaseDetachedAttachmentResources();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _releaseAllAttachmentResources();
    super.dispose();
  }

  void _handleControllerChanged() {
    final status = controller.status;
    final turnEnded =
        _lastRuntimeStatus == RuntimeStatus.running &&
        status != RuntimeStatus.running;
    _lastRuntimeStatus = status;
    if (turnEnded) _releaseDetachedAttachmentResources();
  }

  void _releaseDetachedAttachmentResources() {
    final attachedPaths = _attachments
        .map((attachment) => attachment.path)
        .toSet();
    final paths = <String>{
      ..._securityBookmarks.keys,
      ..._temporaryAttachmentPaths,
    }.where((path) => !attachedPaths.contains(path)).toList(growable: false);
    for (final path in paths) {
      _releaseAttachmentResources(path);
    }
  }

  void _releaseAllAttachmentResources() {
    final paths = <String>{
      ..._securityBookmarks.keys,
      ..._temporaryAttachmentPaths,
    };
    for (final path in paths) {
      _releaseAttachmentResources(path);
    }
  }

  void _releaseAttachmentResources(String path) {
    _releaseSecurityBookmark(path);
    if (_temporaryAttachmentPaths.remove(path)) {
      unawaited(_clipboardFileReader.deleteTemporaryItem(path));
    }
  }

  void _releaseSecurityBookmark(String path) {
    final bookmark = _securityBookmarks.remove(path);
    if (bookmark != null) unawaited(_stopAccessingBookmark(bookmark));
  }

  Future<void> _stopAccessingBookmark(Uint8List bookmark) async {
    try {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    } on MissingPluginException {
      // The host platform does not require macOS security-scoped access.
    } on PlatformException {
      // The resource is already unavailable; there is nothing else to release.
    }
  }

  String get _activityLabel {
    if (controller.status == RuntimeStatus.running) {
      final count = _fileChangeCount;
      return count == 0 ? '正在处理任务' : '正在处理 · $count 个文件已变更';
    }
    return controller.status == RuntimeStatus.ready ? '任务已就绪' : '等待运行时连接';
  }

  Future<void> _submit() async {
    if (controller.canSteer && _hasUnsupportedSteeringContext) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('运行中的调整方向仅支持文本输入。')));
      return;
    }
    final submitted = controller.canSteer
        ? await widget.onSteer(composer.text.trim())
        : await widget.onSend(
            _ComposerSubmission(
              attachments: List.unmodifiable(_attachments),
              includeWorkspace: _includeWorkspace,
              goal: _goal,
              planMode: _planMode,
              recordSkill: _recordSkill,
              skills: _selectedSkills,
            ),
          );
    if (!submitted || !mounted) return;
    setState(() {
      composer.clear();
      _attachments.clear();
      _selectedSkillPaths.clear();
      _includeWorkspace = false;
      _recordSkill = false;
    });
    if (controller.status != RuntimeStatus.running) {
      _releaseDetachedAttachmentResources();
    }
  }

  Future<void> _handleAddAction(_AddMenuAction action) async {
    switch (action.kind) {
      case _AddMenuActionKind.files:
        await _showAttachmentPicker();
      case _AddMenuActionKind.workspace:
        setState(() => _includeWorkspace = !_includeWorkspace);
      case _AddMenuActionKind.goal:
        await _editGoal();
      case _AddMenuActionKind.plan:
        setState(() => _planMode = !_planMode);
      case _AddMenuActionKind.recordSkill:
        setState(() => _recordSkill = !_recordSkill);
      case _AddMenuActionKind.skill:
        final path = action.value;
        if (path == null) return;
        setState(() {
          if (!_selectedSkillPaths.add(path)) {
            _selectedSkillPaths.remove(path);
          }
        });
    }
  }

  Future<void> _showAttachmentPicker() async {
    final choice = await showDialog<_AttachmentPickerKind>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('attachment-picker-dialog'),
        title: const Text('文件和文件夹'),
        content: const Text('选择要随下一条消息发送的文件，或添加一个文件夹路径作为任务上下文。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          OutlinedButton.icon(
            key: const Key('pick-folder-button'),
            onPressed: () =>
                Navigator.pop(dialogContext, _AttachmentPickerKind.folder),
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: const Text('文件夹'),
          ),
          FilledButton.icon(
            key: const Key('pick-files-button'),
            onPressed: () =>
                Navigator.pop(dialogContext, _AttachmentPickerKind.files),
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('文件'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final attachments = switch (choice) {
        _AttachmentPickerKind.files =>
          (await openFiles(confirmButtonText: '附加文件'))
              .map(
                (file) =>
                    _ComposerAttachment(path: file.path, isDirectory: false),
              )
              .toList(growable: false),
        _AttachmentPickerKind.folder => [
          if (await getDirectoryPath(confirmButtonText: '附加文件夹')
              case final path?)
            _ComposerAttachment(path: path, isDirectory: true),
        ],
      };
      if (!mounted || attachments.isEmpty) return;
      _addAttachments(attachments);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开文件选择器。')));
    }
  }

  Future<void> _pasteFromClipboard() async {
    final items = await _clipboardFileReader.readItems();
    if (!mounted) return;
    if (items.isNotEmpty) {
      if (!controller.canSend) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('运行中的调整方向仅支持文本输入。')));
        return;
      }
      _addAttachments(
        items.map(
          (item) => _ComposerAttachment(
            path: item.path,
            isDirectory: item.isDirectory,
            isTemporary: item.isTemporary,
          ),
        ),
      );
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pastedText = data?.text;
    if (!mounted || pastedText == null || pastedText.isEmpty) return;
    final current = composer.text;
    final selection = composer.selection;
    final rawStart = selection.isValid ? selection.start : current.length;
    final rawEnd = selection.isValid ? selection.end : current.length;
    final start = rawStart.clamp(0, current.length);
    final end = rawEnd.clamp(0, current.length);
    final lower = start < end ? start : end;
    final upper = start < end ? end : start;
    composer.value = TextEditingValue(
      text: current.replaceRange(lower, upper, pastedText),
      selection: TextSelection.collapsed(offset: lower + pastedText.length),
    );
  }

  Widget _buildComposerContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    void paste() {
      editableTextState.hideToolbar();
      unawaited(_pasteFromClipboard());
    }

    var hasPaste = false;
    final items = editableTextState.contextMenuButtonItems
        .map((item) {
          if (item.type != ContextMenuButtonType.paste) return item;
          hasPaste = true;
          return item.copyWith(onPressed: paste);
        })
        .toList(growable: true);
    if (!hasPaste) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: paste,
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  Future<void> _handleDroppedFiles(List<DropItem> items) async {
    if (items.isEmpty || !mounted || !controller.canSend) return;
    final attachments = <_ComposerAttachment>[];
    for (final item in items) {
      final path = item.path;
      if (path.isEmpty) continue;
      if (item.extraAppleBookmark case final bookmark?
          when bookmark.isNotEmpty && !_securityBookmarks.containsKey(path)) {
        var accessStarted = false;
        try {
          accessStarted = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
        } on MissingPluginException {
          // The host platform does not require macOS security-scoped access.
        } on PlatformException {
          // Keep the attachment usable on unsandboxed hosts when scope setup fails.
        }
        if (!mounted) {
          if (accessStarted) await _stopAccessingBookmark(bookmark);
          return;
        }
        if (accessStarted) _securityBookmarks[path] = bookmark;
      }
      attachments.add(
        _ComposerAttachment(path: path, isDirectory: item is DropItemDirectory),
      );
    }
    if (!mounted || attachments.isEmpty) return;
    _addAttachments(attachments);
  }

  void _addAttachments(Iterable<_ComposerAttachment> attachments) {
    if (!controller.canSend) return;
    setState(() {
      for (final attachment in attachments) {
        if (attachment.path.isEmpty) continue;
        if (attachment.isTemporary) {
          _temporaryAttachmentPaths.add(attachment.path);
        }
        final index = _attachments.indexWhere(
          (existing) => existing.path == attachment.path,
        );
        if (index < 0) {
          _attachments.add(attachment);
        } else {
          final existing = _attachments[index];
          _attachments[index] = _ComposerAttachment(
            path: attachment.path,
            isDirectory: existing.isDirectory || attachment.isDirectory,
            isTemporary: existing.isTemporary || attachment.isTemporary,
          );
        }
      }
    });
  }

  void _removeAttachment(String path) {
    _releaseAttachmentResources(path);
    setState(() => _attachments.removeWhere((item) => item.path == path));
  }

  Future<void> _showImagePreview(String path) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        key: const Key('composer-image-preview-dialog'),
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.file(
                File(path),
                key: const Key('composer-image-preview'),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox(
                  width: 420,
                  height: 260,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 56,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: '关闭预览',
                color: Colors.white,
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editGoal() async {
    var draft = _goal ?? '';
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('composer-goal-dialog'),
        title: const Text('设置目标'),
        content: SizedBox(
          width: 480,
          child: TextFormField(
            key: const Key('composer-goal-field'),
            initialValue: draft,
            onChanged: (value) => draft = value,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: '描述这个任务需要持续追求的结果'),
          ),
        ),
        actions: [
          if (_goal?.isNotEmpty == true)
            TextButton(
              key: const Key('clear-composer-goal'),
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('清除'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('save-composer-goal'),
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const Text('设置'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _goal = result.isEmpty ? null : result);
  }

  List<PopupMenuEntry<_AddMenuAction>> _buildAddMenu(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final workspace = controller.workspacePath;
    final workspaceName = workspace == null ? '当前项目' : _pathLabel(workspace);
    final entries = <PopupMenuEntry<_AddMenuAction>>[
      _AddMenuHeader(label: '添加', palette: palette),
      _AddMenuItem(
        key: const Key('add-files-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.files),
        icon: Icons.attach_file,
        label: '文件和文件夹',
        selected: _attachments.isNotEmpty,
      ),
      _AddMenuItem(
        key: const Key('add-workspace-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.workspace),
        icon: Icons.terminal_outlined,
        label: '附加 $workspaceName',
        selected: _includeWorkspace,
        enabled: workspace != null,
      ),
      _AddMenuItem(
        key: const Key('add-goal-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.goal),
        icon: Icons.track_changes_outlined,
        label: '目标',
        description: _goal ?? '设置要持续追求的目标',
        selected: _goal?.isNotEmpty == true,
      ),
      _AddMenuItem(
        key: const Key('add-plan-mode-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.plan),
        icon: Icons.lightbulb_outline,
        label: '计划模式',
        description: _planMode ? '已开启计划模式' : '开启计划模式',
        selected: _planMode,
      ),
      _AddMenuItem(
        key: const Key('record-skill-menu-item'),
        value: const _AddMenuAction(_AddMenuActionKind.recordSkill),
        icon: Icons.radio_button_checked,
        label: '录制技能',
        description: _recordSkill ? '将本次流程整理为技能' : null,
        selected: _recordSkill,
      ),
      _AddMenuHeader(label: '插件', palette: palette),
    ];
    if (controller.skillsLoading && controller.skills.isEmpty) {
      entries.add(
        _AddMenuMessage(
          key: Key('composer-skills-loading'),
          label: '正在读取可用技能…',
        ),
      );
    } else if (controller.skills.isEmpty) {
      entries.add(
        _AddMenuMessage(
          key: const Key('composer-skills-empty'),
          label: controller.skillsError ?? '当前项目没有可用技能',
        ),
      );
    } else {
      for (final skill in controller.skills) {
        entries.add(
          _AddMenuItem(
            key: ValueKey('composer-skill-${skill.name}'),
            value: _AddMenuAction(_AddMenuActionKind.skill, skill.path),
            icon: _skillIcon(skill.name),
            label: skill.label,
            description: skill.summary,
            selected: _selectedSkillPaths.contains(skill.path),
          ),
        );
      }
    }
    return entries;
  }

  IconData _skillIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.contains('sheet') || lower.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (lower.contains('presentation') || lower.contains('slide')) {
      return Icons.slideshow_outlined;
    }
    if (lower.contains('document') || lower.contains('doc')) {
      return Icons.description_outlined;
    }
    return Icons.auto_awesome_outlined;
  }

  String _pathLabel(String path) {
    final segments = path
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? path : segments.last;
  }

  /// 构建支持 Enter 发送、Shift+Enter 换行的任务输入面板。
  /// Builds the task composer that sends with Enter and inserts lines with Shift+Enter.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.fileChanges.isNotEmpty)
            _ComposerFileChangePill(
              changes: controller.fileChanges,
              turnDiff: controller.turnDiff,
            )
          else if (controller.activeThreadId != null ||
              controller.status == RuntimeStatus.running)
            _ComposerActivityPill(
              label: _activityLabel,
              active: controller.status == RuntimeStatus.running,
            ),
          DropTarget(
            onDragEntered: (_) {
              if (controller.canSend && mounted) {
                setState(() => _draggingFiles = true);
              }
            },
            onDragExited: (_) {
              if (mounted) setState(() => _draggingFiles = false);
            },
            onDragDone: (details) {
              if (mounted) setState(() => _draggingFiles = false);
              if (!controller.canSend) return;
              unawaited(_handleDroppedFiles(details.files));
            },
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  constraints: const BoxConstraints(minHeight: 126),
                  padding: const EdgeInsets.fromLTRB(16, 13, 12, 10),
                  decoration: BoxDecoration(
                    color: _draggingFiles
                        ? Color.alphaBlend(
                            palette.active.withValues(alpha: 0.08),
                            palette.field,
                          )
                        : palette.field,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _draggingFiles
                          ? palette.active
                          : palette.controlBorder,
                      width: _draggingFiles ? 1.5 : 1,
                    ),
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
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                            ): () {
                              unawaited(_submit());
                            },
                            const SingleActivator(
                              LogicalKeyboardKey.keyV,
                              meta: true,
                            ): () {
                              unawaited(_pasteFromClipboard());
                            },
                            const SingleActivator(
                              LogicalKeyboardKey.keyV,
                              control: true,
                            ): () {
                              unawaited(_pasteFromClipboard());
                            },
                          },
                          child: TextField(
                            key: const Key('composer-field'),
                            controller: composer,
                            enabled: controller.canSend || controller.canSteer,
                            contextMenuBuilder: _buildComposerContextMenu,
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
                      if (_hasComposerContext) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final attachment in _attachments)
                                _ComposerContextChip(
                                  key: ValueKey(
                                    'composer-attachment-${attachment.path}',
                                  ),
                                  icon:
                                      !attachment.isDirectory &&
                                          _isImagePath(attachment.path)
                                      ? Icons.image_outlined
                                      : Icons.attach_file,
                                  thumbnailPath:
                                      !attachment.isDirectory &&
                                          _isImagePath(attachment.path)
                                      ? attachment.path
                                      : null,
                                  label: _pathLabel(attachment.path),
                                  onRemove: () =>
                                      _removeAttachment(attachment.path),
                                  onPreview:
                                      !attachment.isDirectory &&
                                          _isImagePath(attachment.path)
                                      ? () => _showImagePreview(attachment.path)
                                      : null,
                                ),
                              if (_includeWorkspace)
                                _ComposerContextChip(
                                  key: const Key('composer-workspace-chip'),
                                  icon: Icons.terminal_outlined,
                                  label: controller.workspacePath == null
                                      ? '当前项目'
                                      : _pathLabel(controller.workspacePath!),
                                  onRemove: () =>
                                      setState(() => _includeWorkspace = false),
                                ),
                              if (_goal case final goal?)
                                _ComposerContextChip(
                                  key: const Key('composer-goal-chip'),
                                  icon: Icons.track_changes_outlined,
                                  label: goal,
                                  onRemove: () => setState(() => _goal = null),
                                ),
                              if (_planMode)
                                _ComposerContextChip(
                                  key: const Key('composer-plan-mode-chip'),
                                  icon: Icons.lightbulb_outline,
                                  label: '计划模式',
                                  onRemove: () =>
                                      setState(() => _planMode = false),
                                ),
                              if (_recordSkill)
                                _ComposerContextChip(
                                  key: const Key('composer-record-skill-chip'),
                                  icon: Icons.radio_button_checked,
                                  label: '录制技能',
                                  onRemove: () =>
                                      setState(() => _recordSkill = false),
                                ),
                              for (final skill in _selectedSkills)
                                _ComposerContextChip(
                                  key: ValueKey(
                                    'composer-skill-chip-${skill.name}',
                                  ),
                                  icon: _skillIcon(skill.name),
                                  label: skill.label,
                                  onRemove: () => setState(
                                    () =>
                                        _selectedSkillPaths.remove(skill.path),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 9),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final showAttachment = constraints.maxWidth >= 420;
                          final showApproval = constraints.maxWidth >= 340;
                          final showApprovalLabel = constraints.maxWidth >= 460;
                          final showModel = constraints.maxWidth >= 240;
                          return Row(
                            children: [
                              if (showAttachment)
                                PopupMenuButton<_AddMenuAction>(
                                  key: const Key('composer-add-button'),
                                  enabled: controller.canSend,
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
                                    side: BorderSide(
                                      color: palette.controlBorder,
                                    ),
                                  ),
                                  menuPadding: const EdgeInsets.fromLTRB(
                                    8,
                                    8,
                                    8,
                                    10,
                                  ),
                                  onOpened: () {
                                    if (controller.skills.isEmpty &&
                                        !controller.skillsLoading) {
                                      unawaited(controller.refreshSkills());
                                    }
                                  },
                                  onSelected: (action) =>
                                      unawaited(_handleAddAction(action)),
                                  itemBuilder: _buildAddMenu,
                                ),
                              if (showApproval)
                                PopupMenuButton<ApprovalMode>(
                                  tooltip:
                                      '审批模式：${controller.approvalMode.label}',
                                  onSelected: controller.setApprovalMode,
                                  itemBuilder: (context) => ApprovalMode.values
                                      .map(
                                        (mode) => CheckedPopupMenuItem(
                                          value: mode,
                                          checked:
                                              controller.approvalMode == mode,
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
                                            controller.approvalMode.label,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              if (showModel) ...[
                                _ComposerModelControls(
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
                                  ),
                                  icon: const Icon(Icons.stop, size: 19),
                                )
                              else
                                IconButton.filled(
                                  tooltip: '发送任务',
                                  onPressed: controller.canSend
                                      ? _submit
                                      : null,
                                  style: IconButton.styleFrom(
                                    backgroundColor: scheme.primary,
                                    foregroundColor: scheme.onPrimary,
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_upward,
                                    size: 19,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (_draggingFiles)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Semantics(
                        key: const Key('composer-drop-overlay'),
                        liveRegion: true,
                        label: '松开即可添加文件',
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.active.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: palette.raised,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: palette.active.withValues(alpha: 0.65),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.file_upload_outlined,
                                    size: 20,
                                    color: palette.active,
                                  ),
                                  const SizedBox(width: 9),
                                  Text(
                                    '松开即可添加文件',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: palette.trace,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AttachmentPickerKind { files, folder }

enum _AddMenuActionKind { files, workspace, goal, plan, recordSkill, skill }

class _AddMenuAction {
  const _AddMenuAction(this.kind, [this.value]);

  final _AddMenuActionKind kind;
  final String? value;
}

class _ComposerAttachment {
  const _ComposerAttachment({
    required this.path,
    required this.isDirectory,
    this.isTemporary = false,
  });

  final String path;
  final bool isDirectory;
  final bool isTemporary;
}

class _ComposerSubmission {
  const _ComposerSubmission({
    required this.attachments,
    required this.includeWorkspace,
    required this.goal,
    required this.planMode,
    required this.recordSkill,
    required this.skills,
  });

  final List<_ComposerAttachment> attachments;
  final bool includeWorkspace;
  final String? goal;
  final bool planMode;
  final bool recordSkill;
  final List<CodexSkill> skills;

  bool get hasContext =>
      attachments.isNotEmpty ||
      includeWorkspace ||
      goal?.isNotEmpty == true ||
      planMode ||
      recordSkill ||
      skills.isNotEmpty;
}

class _AddMenuHeader extends PopupMenuEntry<_AddMenuAction> {
  const _AddMenuHeader({required this.label, required this.palette});

  final String label;
  final YeknomPalette palette;

  @override
  double get height => 34;

  @override
  bool represents(_AddMenuAction? value) => false;

  @override
  State<_AddMenuHeader> createState() => _AddMenuHeaderState();
}

class _AddMenuHeaderState extends State<_AddMenuHeader> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        widget.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: widget.palette.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _AddMenuItem extends PopupMenuItem<_AddMenuAction> {
  _AddMenuItem({
    required super.value,
    required this.icon,
    required this.label,
    required this.selected,
    this.description,
    super.enabled = true,
    super.key,
  }) : super(
         height: 50,
         padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
         child: _AddMenuRow(
           icon: icon,
           label: label,
           description: description,
           selected: selected,
           enabled: enabled,
         ),
       );

  final IconData icon;
  final String label;
  final String? description;
  final bool selected;
}

class _AddMenuMessage extends PopupMenuItem<_AddMenuAction> {
  _AddMenuMessage({required String label, super.key})
    : super(
        enabled: false,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label),
      );
}

class _AddMenuRow extends StatelessWidget {
  const _AddMenuRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    this.description,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final titleColor = enabled ? palette.trace : palette.muted;
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.raised : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Icon(icon, size: 21, color: titleColor),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (description?.trim().isNotEmpty == true) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: palette.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, size: 17, color: palette.active),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerContextChip extends StatelessWidget {
  const _ComposerContextChip({
    required this.icon,
    required this.label,
    required this.onRemove,
    this.thumbnailPath,
    this.onPreview,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onRemove;
  final String? thumbnailPath;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thumbnailPath case final thumbnail?)
            InkWell(
              key: const Key('composer-image-thumbnail'),
              onTap: onPreview,
              borderRadius: BorderRadius.circular(7),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Image.file(
                    File(thumbnail),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: palette.field,
                      child: Icon(icon, size: 18, color: palette.muted),
                    ),
                  ),
                ),
              ),
            )
          else
            Icon(icon, size: 15, color: palette.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 3),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: palette.muted),
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
                  ? '帮我批准命令、文件变更和额外权限请求。'
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

/// 展示可搜索、可按状态筛选的只读 Git 项目对话框。
/// Displays a searchable, status-filterable, read-only Git project dialog.
class _GitProjectDialog extends StatefulWidget {
  const _GitProjectDialog({required this.controller});

  final CodexController controller;

  @override
  State<_GitProjectDialog> createState() => _GitProjectDialogState();
}

class _GitProjectDialogState extends State<_GitProjectDialog> {
  final TextEditingController _search = TextEditingController();
  GitChangeFilter _filter = GitChangeFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 构建筛选控件、文件列表和当前只读 Diff 预览。
  /// Builds filter controls, the file list, and the selected read-only diff preview.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
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
                const Text('只读视图：不会执行暂存、还原、提交、切分支、拉取或推送。'),
                const SizedBox(height: 12),
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
                                      onTap: () =>
                                          controller.showGitDiff(change),
                                    );
                                  },
                                ),
                        ),
                        const VerticalDivider(width: 24),
                        Expanded(
                          child: _GitDiffViewer(
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
      },
    );
  }
}

/// 展示只读 Git Diff 的详情面板，不包含暂存、恢复或写入仓库的操作。
/// Displays a read-only Git diff detail panel without staging, restoring, or repository write actions.
class _GitDiffViewer extends StatelessWidget {
  const _GitDiffViewer({
    required this.change,
    required this.diff,
    required this.loading,
    required this.truncated,
  });

  final GitProjectChange? change;
  final String? diff;
  final bool loading;
  final bool truncated;

  /// 构建所选 Git 文件的加载、空状态或可复制 Diff 内容。
  /// Builds loading, empty, or copyable diff content for the selected Git file.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (change == null) return const Center(child: Text('从左侧选择一个文件查看 Diff。'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          change!.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (truncated) ...[
          Container(
            key: const Key('git-diff-truncated-warning'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.warning),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Diff 过大，当前仅显示前 120,000 个字符。')),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: diff == null
                ? const Center(child: Text('正在准备 Diff。'))
                : diff!.isEmpty
                ? const Center(child: Text('Git 未返回可显示的 Diff。'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        diff!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry(this.entry, {this.onAdjustDirection});

  final TimelineEntry entry;
  final VoidCallback? onAdjustDirection;

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
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(entry.detail),
              ),
              if (onAdjustDirection != null) ...[
                const SizedBox(height: 5),
                TextButton.icon(
                  key: const Key('adjust-direction-button'),
                  onPressed: onAdjustDirection,
                  icon: const Icon(Icons.reply_outlined, size: 17),
                  label: const Text('调整方向'),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.muted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
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
    required this.pinned,
    required this.enabled,
    required this.selectionMode,
    required this.batchSelected,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
    required this.onDelete,
    required this.onTogglePin,
  });

  final CodexThread thread;
  final bool selected;
  final bool pinned;
  final bool enabled;
  final bool selectionMode;
  final bool batchSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

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
              if (selectionMode)
                Checkbox(
                  value: batchSelected,
                  onChanged: enabled ? (_) => onTap() : null,
                )
              else
                Icon(
                  pinned
                      ? Icons.push_pin
                      : selected
                      ? Icons.forum
                      : Icons.forum_outlined,
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
                enabled: enabled && !selectionMode,
                onSelected: (action) {
                  switch (action) {
                    case _ThreadAction.rename:
                      onRename();
                    case _ThreadAction.archive:
                      onArchive();
                    case _ThreadAction.delete:
                      onDelete();
                    case _ThreadAction.pin:
                      onTogglePin();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _ThreadAction.pin,
                    child: Text(pinned ? '取消置顶' : '置顶'),
                  ),
                  const PopupMenuItem(
                    value: _ThreadAction.rename,
                    child: Text('重命名'),
                  ),
                  const PopupMenuItem(
                    value: _ThreadAction.archive,
                    child: Text('归档'),
                  ),
                  const PopupMenuItem(
                    value: _ThreadAction.delete,
                    child: Text('永久删除'),
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

enum _ThreadAction { pin, rename, archive, delete }

enum _HistoryAction { archived, batchArchive, export, import }

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
    required this.onDelete,
  });

  final CodexThread thread;
  final bool enabled;
  final bool restoring;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  /// 构建带恢复操作与进行状态的归档线程项。
  /// Builds an archived-thread item with restore action and progress state.
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: thread.status == null ? null : Text(thread.status!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: enabled ? onRestore : null,
            icon: restoring
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.unarchive_outlined, size: 18),
            label: Text(restoring ? '恢复中' : '恢复'),
          ),
          IconButton(
            tooltip: '永久删除任务',
            onPressed: enabled && !restoring ? onDelete : null,
            icon: const Icon(Icons.delete_outline),
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
