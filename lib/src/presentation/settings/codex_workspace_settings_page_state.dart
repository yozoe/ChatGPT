import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_page.dart';
import 'package:chatgpt/src/services/dock_icon_service.dart';
import 'package:chatgpt/src/domain/worktree_settings.dart';
import 'package:chatgpt/src/domain/agent_setting_field.dart';
import 'package:chatgpt/src/domain/agent_setting_availability.dart';
import 'package:chatgpt/src/domain/local_worktree_record.dart';
import 'package:chatgpt/src/services/local_worktree_service.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_worktrees_section.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_archived_chats_section.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_browser_section.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_plugins_section.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_appearance_section.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_help_actions.dart';

/// 管理设置页面的局部导航和临时显示偏好。
/// Owns settings-page local navigation and transient display preferences.
final codexHooksProvider = FutureProvider.autoDispose
    .family<List<CodexHook>, CodexController>(
      (ref, controller) => controller.listCodexHooks(),
    );

class SettingsPageState extends ConsumerState<SettingsPage> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _archiveSearch = TextEditingController();
  String _section = '常规';
  String _archiveTypeFilter = '全部聊天';
  String _archiveProjectFilter = '当前项目';
  final String _defaultEditor = 'VS Code';
  final bool _showInMenuBar = true;
  final bool _showBottomPanel = true;
  final String _terminalPosition = '底部';
  final bool _preventSleep = false;
  final bool _promptSuggestions = false;
  final bool _usePointerCursor = false;
  final String _reduceMotion = '系统';
  final String _diffMarkers = '颜色';
  final bool _fontSmoothing = true;
  int _dockIcon = 0;
  final DockIconService _dockIconService = DockIconService();
  final TextEditingController _uiFontSize = TextEditingController(text: '14');
  final TextEditingController _codeFontSize = TextEditingController(text: '13');
  late final TextEditingController _worktreeRoot;
  late final TextEditingController _worktreeRetention;
  WorktreeSettings _worktreeSettings = WorktreeSettings.defaults();
  List<LocalWorktreeRecord> _worktrees = const [];
  bool _worktreesLoading = true;
  String? _worktreesError;
  late final LocalWorktreeService _worktreeService = LocalWorktreeService(
    store: widget.runtimeConfigurationStore,
  );

  @override
  void initState() {
    super.initState();
    _restoreDockIconSelection();
    _worktreeRoot = TextEditingController(text: _worktreeSettings.rootPath);
    _worktreeRetention = TextEditingController(text: '15');
    _loadWorktrees();
  }

  @override
  void dispose() {
    _search.dispose();
    _archiveSearch.dispose();
    _uiFontSize.dispose();
    _codeFontSize.dispose();
    _worktreeRoot.dispose();
    _worktreeRetention.dispose();
    super.dispose();
  }

  Future<void> _loadWorktrees() async {
    try {
      final values = await Future.wait([
        widget.runtimeConfigurationStore.readWorktreeSettings(),
        widget.runtimeConfigurationStore.readWorktreeRecords(),
      ]);
      if (!mounted) return;
      setState(() {
        _worktreeSettings = values[0] as WorktreeSettings;
        _worktrees = values[1] as List<LocalWorktreeRecord>;
        _worktreeRoot.text = _worktreeSettings.rootPath;
        _worktreeRetention.text = '${_worktreeSettings.retentionLimit}';
        _worktreesLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _worktreesLoading = false;
        _worktreesError = '$error';
      });
    }
  }

  Future<void> _saveWorktreeSettings(WorktreeSettings next) async {
    if (next.rootPath.trim().isEmpty ||
        !Directory(next.rootPath.trim()).isAbsolute) {
      if (mounted) {
        setState(() => _worktreesError = '工作树根目录必须是绝对路径。');
      }
      return;
    }
    _worktreesError = null;
    setState(() => _worktreeSettings = next);
    await widget.runtimeConfigurationStore.saveWorktreeSettings(next);
  }

  Future<void> _restoreWorktree(LocalWorktreeRecord record) async {
    try {
      await _worktreeService.restore(
        record: record,
        rootPath: _worktreeSettings.rootPath,
      );
      await _loadWorktrees();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _worktreesError = '$error');
    }
  }

  Widget _worktreesContent() {
    return SettingsWorktreesSection(
      rootController: _worktreeRoot,
      retentionController: _worktreeRetention,
      settings: _worktreeSettings,
      worktrees: _worktrees,
      loading: _worktreesLoading,
      error: _worktreesError,
      buildSettingRow: _settingRow,
      onSaveSettings: _saveWorktreeSettings,
      onRestoreWorktree: _restoreWorktree,
      onRefresh: _loadWorktrees,
    );
  }

  void _select(String section) => setState(() => _section = section);

  void _handleSettingsSearch(String value) {
    final query = value.trim().toLowerCase();
    if (query.isEmpty) return;
    const targets = <String, String>{
      '常规 项目 编辑器 终端 休眠 提示词': '常规',
      '外观 主题 图标 字号 动画 diff 字体': '外观',
      '配置 模型 权限 sandbox runtime': '配置',
      '插件 mcp 技能': '插件',
      '浏览器 网页': '浏览器',
      'worktrees 工作树 工作树根目录': 'Worktrees',
      '钩子 hooks': '钩子',
      '归档 聊天 历史': '已归档的聊天',
    };
    final match = targets.entries
        .where((entry) => entry.key.contains(query))
        .firstOrNull;
    if (match != null && match.value != _section) {
      setState(() => _section = match.value);
    }
  }

  void _selectArchivedChats() {
    setState(() {
      _section = '已归档的聊天';
      _archiveSearch.clear();
    });
    unawaited(widget.controller.refreshArchivedThreads());
  }

  /// 打开浏览器能力说明；浏览器工作区只能由智能体协议按需唤起。
  /// Opens browser capability settings; the browser workspace can only be invoked on demand by the agent protocol.
  void _selectBrowser() => _select('浏览器');

  Future<void> _chooseBrowserDownloadDirectory() async {
    final directory = await getDirectoryPath(
      initialDirectory: widget.controller.browserDownloadDirectory,
      confirmButtonText: '选择下载目录',
    );
    if (directory != null) {
      unawaited(widget.controller.setBrowserDownloadDirectory(directory));
    }
  }

  /// 构建只管理策略、不手动创建 WebView 的浏览器设置内容。
  /// Builds browser settings that manage policy without manually creating a WebView.
  Widget _browserContent() {
    return SettingsBrowserSection(
      controller: widget.controller,
      onChooseDownloadDirectory: _chooseBrowserDownloadDirectory,
    );
  }

  /// 进入扩展管理页并并行刷新插件、MCP 与技能目录。
  /// Opens extension management and refreshes plugins, MCP servers, and skills in parallel.
  void _selectPlugins() {
    setState(() => _section = '插件');
    unawaited(
      Future.wait([
        widget.controller.refreshPlugins(),
        widget.controller.refreshMcpServers(),
        widget.controller.refreshSkills(forceReload: true),
      ]),
    );
  }

  /// 将原插件对话框嵌入设置内容区，保持两种入口共享同一管理界面。
  /// Embeds the existing extension dialog in settings so both entry points share one UI.
  Widget _pluginsContent() {
    return SettingsPluginsSection(
      controller: widget.controller,
      onAddMarketplace: widget.onAddMarketplace,
      onManageMarketplaces: widget.onManageMarketplaces,
    );
  }

  void _refreshHooks() => ref.invalidate(codexHooksProvider(widget.controller));

  Future<void> _selectDockIcon(int index) async {
    final selected = await _dockIconService.select(
      index == 0 ? 'knot' : 'commandCloud',
    );
    if (!mounted || !selected) return;
    setState(() => _dockIcon = index);
  }

  Future<void> _restoreDockIconSelection() async {
    final icon = await _dockIconService.selected();
    if (!mounted || icon == null) return;
    setState(() => _dockIcon = icon == 'commandCloud' ? 1 : 0);
  }

  Widget _navItem({
    required String label,
    required IconData icon,
    bool selected = false,
    VoidCallback? onTap,
    bool trailingArrow = false,
  }) {
    final palette = YeknomPalette.of(context);
    final enabled = onTap != null || !label.contains('（待开发）');
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: InkWell(
        key: Key('settings-nav-$label'),
        onTap: enabled ? (onTap ?? () => _select(label)) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? palette.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? palette.trace : palette.faint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: enabled ? null : TextStyle(color: palette.faint),
                ),
              ),
              if (trailingArrow)
                Icon(Icons.arrow_outward, size: 16, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: YeknomPalette.of(context).muted,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _settingRow({
    required String title,
    required String description,
    Widget? trailing,
  }) {
    final palette = YeknomPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(color: palette.muted, height: 1.35),
            ),
          ],
        );
        final narrow = constraints.maxWidth < 500;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    if (trailing != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Semantics(label: title, child: trailing),
                      ),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: details),
                    if (trailing != null) ...[
                      const SizedBox(width: 24),
                      Semantics(label: title, child: trailing),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _generalContent() {
    final palette = YeknomPalette.of(context);
    final workspacePath = widget.controller.workspacePath;
    return ListView(
      key: const Key('settings-general-page'),
      padding: const EdgeInsets.fromLTRB(72, 46, 72, 72),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '常规',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 38,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 42),
              Text(
                '权限',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    _settingRow(
                      title: '默认权限',
                      description:
                          '默认情况下，Codex 可以读取和编辑其工作空间中的文件。需要时，它可以请求额外访问权限。',
                      trailing: Switch(
                        value:
                            widget.controller.approvalMode ==
                            ApprovalMode.manual,
                        onChanged: (value) => widget.controller.setApprovalMode(
                          value
                              ? ApprovalMode.manual
                              : ApprovalMode.autoApprove,
                        ),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '完整访问权限',
                      description: '允许 Codex 在无需逐次批准的情况下访问更多文件和网络命令。',
                      trailing: Switch(
                        value:
                            widget.controller.approvalMode ==
                            ApprovalMode.autoApprove,
                        onChanged: (value) => widget.controller.setApprovalMode(
                          value
                              ? ApprovalMode.autoApprove
                              : ApprovalMode.manual,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 44),
              Text(
                '常规',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    _settingRow(
                      title: '无项目任务文件夹',
                      description: '在项目外启动的任务默认存储数据的位置。',
                      trailing: TextButton(
                        key: const Key('settings-change-task-folder'),
                        onPressed: widget.onChooseWorkspace,
                        child: Text(workspacePath == null ? '选择' : '更改'),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '默认文件打开位置（待开发）',
                      description: '默认打开文件和文件夹的位置。',
                      trailing: PopupMenuButton<String>(
                        key: const Key('settings-default-editor'),
                        initialValue: _defaultEditor,
                        enabled: false,
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'VS Code',
                            child: Text('VS Code'),
                          ),
                          PopupMenuItem(value: 'Cursor', child: Text('Cursor')),
                          PopupMenuItem(value: '系统默认', child: Text('系统默认')),
                        ],
                        child: Chip(
                          label: Text(_defaultEditor),
                          deleteIcon: const Icon(Icons.expand_more),
                          onDeleted: () {},
                        ),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '语言',
                      description: '应用 UI 语言',
                      trailing: const Chip(label: Text('自动检测')),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '在菜单栏中显示（待开发）',
                      description: '关闭主窗口后，仍在 macOS 菜单栏中保留 Codex Desk',
                      trailing: Switch(value: _showInMenuBar, onChanged: null),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '底部面板（待开发）',
                      description: '在应用标题栏中显示底部面板控件',
                      trailing: Switch(
                        value: _showBottomPanel,
                        onChanged: null,
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '默认终端位置（待开发）',
                      description: '选择终端快捷键和环境操作在何处打开终端标签页',
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '底部', label: Text('底部')),
                          ButtonSegment(value: '右侧', label: Text('右侧')),
                        ],
                        selected: {_terminalPosition},
                        onSelectionChanged: null,
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '运行时防止系统休眠（待开发）',
                      description: '在 Codex Desk 运行任务时，让电脑保持唤醒状态',
                      trailing: Switch(value: _preventSleep, onChanged: null),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '提示词建议（待开发）',
                      description: '通过搜索项目文件和已连接的应用，建议下一步操作',
                      trailing: Switch(
                        value: _promptSuggestions,
                        onChanged: null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _appearanceContent() {
    return SettingsAppearanceSection(
      uiFontSize: _uiFontSize,
      codeFontSize: _codeFontSize,
      dockIcon: _dockIcon,
      highContrast: widget.highContrast,
      onHighContrastChanged: widget.onHighContrastChanged,
      onSelectDockIcon: _selectDockIcon,
      buildSettingRow: _settingRow,
      usePointerCursor: _usePointerCursor,
      reduceMotion: _reduceMotion,
      diffMarkers: _diffMarkers,
      fontSmoothing: _fontSmoothing,
    );
  }

  static const _inheritAgentDefaultValue = '__codex_desk_inherit__';

  Future<void> _writeAgentDefaultSetting(String keyPath, String? value) async {
    try {
      await widget.controller.writeAgentDefaultSetting(
        keyPath: keyPath,
        value: value,
      );
    } catch (_) {
      // The controller retains the error and the previous effective snapshot.
    }
    if (mounted) setState(() {});
  }

  Widget _agentDefaultValueControl({
    required String keyPath,
    required AgentSettingField field,
    required Map<String, String> options,
    required String inheritedLabel,
  }) {
    final palette = YeknomPalette.of(context);
    final display = field.availability == AgentSettingAvailability.missing
        ? '由配置管理'
        : field.value == null
        ? inheritedLabel
        : options[field.value] ?? field.value!;
    final editable =
        widget.controller.agentDefaultSettingsWriteSupported &&
        field.isRuntimeExposed &&
        field.isScalarValue;
    if (!editable) {
      return Text(display, style: TextStyle(color: palette.muted));
    }
    return PopupMenuButton<String>(
      key: ValueKey('settings-configuration-$keyPath'),
      initialValue: field.value ?? _inheritAgentDefaultValue,
      onSelected: (value) => unawaited(
        _writeAgentDefaultSetting(
          keyPath,
          value == _inheritAgentDefaultValue ? null : value,
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: _inheritAgentDefaultValue,
          child: Text(inheritedLabel),
        ),
        ...options.entries.map(
          (entry) =>
              PopupMenuItem<String>(value: entry.key, child: Text(entry.value)),
        ),
      ],
      child: Chip(label: Text(display)),
    );
  }

  String _approvalPolicyDisplay(AgentSettingField field) {
    if (field.availability == AgentSettingAvailability.missing) {
      return '由配置管理';
    }
    if (field.value == null) return '继承默认值';
    if (!field.isScalarValue) return '细粒度策略（由配置管理）';
    return switch (field.value) {
      'untrusted' => '不受信任时请求',
      'on-request' => '按请求',
      'never' => '从不',
      _ => field.value!,
    };
  }

  Widget _configurationContent() {
    final palette = YeknomPalette.of(context);
    final defaults = widget.controller.agentDefaultSettings;
    String settingDescription(String description, AgentSettingField field) {
      final source = field.source;
      if (source == null || source.isEmpty) return description;
      return '$description\n来源：$source';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return ListView(
          key: const Key('settings-configuration-page'),
          padding: EdgeInsets.fromLTRB(
            compact ? 24 : 72,
            46,
            compact ? 24 : 72,
            72,
          ),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '配置',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 38,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '配置新聊天的权限、运行时状态和模型能力。',
                    style: TextStyle(color: palette.muted),
                  ),
                  const SizedBox(height: 34),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '智能体默认设置',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      TextButton.icon(
                        key: const Key('settings-open-codex-configuration'),
                        onPressed: widget.onShowCodexConfiguration,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('查看模型与 Provider 状态'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.raised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      children: [
                        _settingRow(
                          title: 'Codex 批准策略',
                          description: settingDescription(
                            '这是 App Server 解析后的实际默认策略；复杂的细粒度策略保持只读，不会被简化成单一枚举。',
                            defaults.approvalPolicy,
                          ),
                          trailing: Text(
                            _approvalPolicyDisplay(defaults.approvalPolicy),
                            key: const Key(
                              'settings-configuration-effective-approval-policy',
                            ),
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '应用内审批行为',
                          description:
                              '仅控制本应用如何响应后续任务的权限请求，不改写 Codex 配置中的官方批准策略。',
                          trailing: PopupMenuButton<ApprovalMode>(
                            key: const Key(
                              'settings-configuration-approval-mode',
                            ),
                            initialValue: widget.controller.approvalMode,
                            onSelected: (value) async {
                              await widget.controller.setApprovalMode(value);
                              if (mounted) setState(() {});
                            },
                            itemBuilder: (context) => ApprovalMode.values
                                .map(
                                  (mode) => PopupMenuItem(
                                    value: mode,
                                    child: Text(mode.label),
                                  ),
                                )
                                .toList(),
                            child: Chip(
                              label: Text(widget.controller.approvalMode.label),
                            ),
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '用户配置 Profile',
                          description: settingDescription(
                            '显示 App Server 解析后的当前 Profile；切换 Profile 仍通过 Codex 配置文件完成。',
                            AgentSettingField(
                              availability: defaults.profile == null
                                  ? AgentSettingAvailability.missing
                                  : AgentSettingAvailability.explicit,
                              value: defaults.profile,
                              source: defaults.profileSource,
                            ),
                          ),
                          trailing: Text(
                            defaults.profile ?? '由配置管理',
                            key: const Key('settings-configuration-profile'),
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '沙盒设置',
                          description: settingDescription(
                            '文件与命令的实际访问范围由 Codex App Server 和项目权限决定。',
                            defaults.sandboxMode,
                          ),
                          trailing: _agentDefaultValueControl(
                            keyPath: 'sandbox_mode',
                            field: defaults.sandboxMode,
                            inheritedLabel: '继承默认值',
                            options: const {
                              'read-only': '只读',
                              'workspace-write': '工作区可写',
                              'danger-full-access': '完全访问',
                            },
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '网页搜索',
                          description: settingDescription(
                            '网络访问能力由当前 Codex 运行时及其配置决定。',
                            defaults.webSearch,
                          ),
                          trailing: _agentDefaultValueControl(
                            keyPath: 'web_search',
                            field: defaults.webSearch,
                            inheritedLabel: '继承默认值',
                            options: const {
                              'disabled': '关闭',
                              'cached': '缓存',
                              'indexed': '索引',
                              'live': '实时',
                            },
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '输出详细程度',
                          description: settingDescription(
                            '回复风格由所选模型和 Codex 配置决定；本应用不会覆盖它。',
                            defaults.modelVerbosity,
                          ),
                          trailing: _agentDefaultValueControl(
                            keyPath: 'model_verbosity',
                            field: defaults.modelVerbosity,
                            inheritedLabel: '模型默认',
                            options: const {
                              'low': '低',
                              'medium': '中',
                              'high': '高',
                            },
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '推理摘要',
                          description: settingDescription(
                            '是否提供摘要由模型和运行时能力协商，本应用会原样显示可用结果。',
                            defaults.reasoningSummary,
                          ),
                          trailing: _agentDefaultValueControl(
                            keyPath: 'model_reasoning_summary',
                            field: defaults.reasoningSummary,
                            inheritedLabel: '自动',
                            options: const {
                              'auto': '自动',
                              'concise': '简洁',
                              'detailed': '详细',
                              'none': '不显示',
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.controller.agentDefaultSettingsWriteError !=
                      null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '写入失败：${widget.controller.agentDefaultSettingsWriteError}',
                      style: TextStyle(color: palette.fault),
                    ),
                  ],
                  const SizedBox(height: 44),
                  Text(
                    '模型功能',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.raised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      children: [
                        _settingRow(
                          title: '默认推理强度',
                          description: '选择后续新任务的推理强度。可用选项会随当前模型自动更新。',
                          trailing: PopupMenuButton<ReasoningEffort>(
                            key: const Key(
                              'settings-configuration-reasoning-effort',
                            ),
                            initialValue: widget.controller.reasoningEffort,
                            onSelected: (value) async {
                              await widget.controller.setReasoningEffort(value);
                              if (mounted) setState(() {});
                            },
                            itemBuilder: (context) => widget
                                .controller
                                .reasoningEffortOptions
                                .map(
                                  (effort) => PopupMenuItem(
                                    value: effort,
                                    child: Text(effort.label),
                                  ),
                                )
                                .toList(),
                            child: Chip(
                              label: Text(
                                widget.controller.reasoningEffort.label,
                              ),
                            ),
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '模型能力状态',
                          description:
                              '模型和 Provider 会从当前工作区的最终生效配置读取，不会在这里保存密钥或 Base URL。',
                          trailing: TextButton(
                            onPressed: widget.onShowCodexConfiguration,
                            child: const Text('查看状态'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 44),
                  Text(
                    '工作空间依赖项',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.raised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      children: [
                        _settingRow(
                          title: 'Codex CLI 运行时',
                          description: '检查本机 Codex CLI、已解析的可执行文件和最近的运行时诊断日志。',
                          trailing: OutlinedButton.icon(
                            key: const Key(
                              'settings-configuration-diagnose-runtime',
                            ),
                            onPressed: widget.onConfigureRuntime,
                            icon: const Icon(
                              Icons.manage_search_outlined,
                              size: 18,
                            ),
                            label: const Text('诊断'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _hooksContent() {
    final palette = YeknomPalette.of(context);
    final hooks = ref.watch(codexHooksProvider(widget.controller));
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return ListView(
          key: const Key('settings-hooks-page'),
          padding: EdgeInsets.fromLTRB(
            compact ? 24 : 72,
            46,
            compact ? 24 : 72,
            72,
          ),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '钩子',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text.rich(
                              key: const Key('settings-hooks-description'),
                              TextSpan(
                                text: '通过配置和已启用的插件管理生命周期钩子。',
                                style: TextStyle(color: palette.muted),
                                children: [
                                  TextSpan(
                                    text: ' 了解更多',
                                    style: TextStyle(color: palette.active),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: '刷新钩子列表',
                        child: IconButton(
                          key: const Key('settings-hooks-refresh'),
                          tooltip: '刷新钩子列表',
                          onPressed: _refreshHooks,
                          icon: const Icon(Icons.refresh_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 46),
                  hooks.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _hooksMessage(
                      key: const Key('settings-hooks-error-state'),
                      title: '无法读取钩子',
                      detail: '$error',
                    ),
                    data: (items) => items.isEmpty
                        ? _hooksMessage(
                            key: const Key('settings-hooks-empty-state'),
                            title: '未找到钩子',
                            detail: 'Codex 已检查项目、用户配置和已启用插件。',
                          )
                        : _hooksList(items),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _hooksMessage({
    required Key key,
    required String title,
    required String detail,
  }) => DecoratedBox(
    key: key,
    decoration: BoxDecoration(
      color: YeknomPalette.of(context).raised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: YeknomPalette.of(context).border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: TextStyle(color: YeknomPalette.of(context).muted),
          ),
        ],
      ),
    ),
  );

  Widget _hooksList(List<CodexHook> hooks) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '由 Codex 发现的钩子',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 18),
      for (final hook in hooks) ...[
        _hookTile(
          hook,
          key: Key('settings-hook-${hook.key}'),
          onTap: () => _showHooks(hooks),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );

  Widget _hookTile(
    CodexHook hook, {
    required Key key,
    required VoidCallback onTap,
  }) {
    final palette = YeknomPalette.of(context);
    return Material(
      key: key,
      color: palette.raised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          hook.source == 'plugin'
              ? Icons.extension_outlined
              : Icons.anchor_outlined,
        ),
        title: Text(hook.eventName),
        subtitle: Text(
          '${hook.source}${hook.pluginId == null ? '' : ' · ${hook.pluginId}'}',
        ),
        trailing: hook.isTrusted
            ? const Icon(Icons.verified_outlined, color: Colors.green)
            : Icon(Icons.error_outline, color: Colors.orange.shade700),
      ),
    );
  }

  Future<void> _showHooks(List<CodexHook> hooks) => showDialog<void>(
    context: context,
    builder: (context) {
      final palette = YeknomPalette.of(context);
      return Dialog(
        child: Material(
          color: palette.raised,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 700,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.anchor_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '钩子详情',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF211713),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('钩子可在沙盒外运行，因此，请审查最近安装或修改的所有钩子'),
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: hooks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _hookDetails(hooks[index]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _hookDetails(CodexHook hook) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: YeknomPalette.of(context).border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hook.eventName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            '${hook.source} · ${hook.sourcePath}',
            style: TextStyle(color: YeknomPalette.of(context).muted),
          ),
          if (hook.command != null) SelectableText('命令　${hook.command}'),
          if (hook.timeoutSec != null) Text('超时　${hook.timeoutSec}秒'),
          SwitchListTile(
            key: Key('settings-hook-enabled-${hook.key}'),
            contentPadding: EdgeInsets.zero,
            title: const Text('已启用'),
            value: hook.enabled,
            onChanged: (value) => _setHookEnabled(hook, value),
          ),
          OutlinedButton.icon(
            onPressed: () => _setHookTrusted(hook, !hook.isTrusted),
            icon: Icon(
              hook.isTrusted
                  ? Icons.remove_moderator_outlined
                  : Icons.verified_user_outlined,
            ),
            label: Text(hook.isTrusted ? '撤销信任' : '信任此版本'),
          ),
        ],
      ),
    ),
  );

  Future<void> _setHookEnabled(CodexHook hook, bool value) async {
    try {
      await widget.controller.setCodexHookEnabled(hook, value);
      _refreshHooks();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法更新钩子：$error')));
      }
    }
  }

  Future<void> _setHookTrusted(CodexHook hook, bool value) async {
    try {
      await widget.controller.setCodexHookTrusted(hook, value);
      _refreshHooks();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法更新钩子信任：$error')));
      }
    }
  }

  String _archiveProjectName() {
    final path = widget.controller.workspacePath;
    if (path == null || path.trim().isEmpty) return '当前项目';
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? '当前项目' : parts.last;
  }

  String _archiveDate(CodexThread thread) {
    if (thread.updatedAt <= 0) return '';
    final raw = thread.updatedAt < 100000000000
        ? thread.updatedAt * 1000
        : thread.updatedAt;
    final date = DateTime.fromMillisecondsSinceEpoch(raw).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}年${date.month}月${date.day}日，${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _deleteArchivedThread(CodexThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除聊天？'),
        content: Text('“${thread.title}”将从 Codex 中永久删除，无法恢复。'),
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
    if (confirmed == true) await widget.controller.deleteThread(thread);
  }

  Future<void> _deleteAllArchivedThreads() async {
    final threads = List<CodexThread>.of(widget.controller.archivedThreads);
    if (threads.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除所有已归档的聊天？'),
        content: Text('共 ${threads.length} 个聊天将被永久删除，无法恢复。'),
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
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final thread in threads) {
      await widget.controller.deleteThread(thread);
    }
  }

  Widget _archivedContent() {
    return SettingsArchivedChatsSection(
      controller: widget.controller,
      archiveSearch: _archiveSearch,
      archiveTypeFilter: _archiveTypeFilter,
      archiveProjectFilter: _archiveProjectFilter,
      projectName: _archiveProjectName(),
      buildMessage: _hooksMessage,
      archiveDate: _archiveDate,
      onSearchChanged: () => setState(() {}),
      onTypeFilterChanged: (value) =>
          setState(() => _archiveTypeFilter = value),
      onProjectFilterChanged: (value) =>
          setState(() => _archiveProjectFilter = value),
      onDeleteThread: _deleteArchivedThread,
      onDeleteAllThreads: _deleteAllArchivedThreads,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Row(
        key: const Key('settings-page'),
        children: [
          SizedBox(
            key: const Key('settings-navigation-pane'),
            width: widget.navigationWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.bench,
                border: Border(right: BorderSide(color: palette.border)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 22, 12, 14),
                      child: Column(
                        children: [
                          TextButton.icon(
                            key: const Key('settings-back-button'),
                            onPressed: widget.onOpenConversation,
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('返回应用'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('settings-search-field'),
                            controller: _search,
                            onChanged: _handleSettingsSearch,
                            decoration: const InputDecoration(
                              hintText: '搜索设置...',
                              prefixIcon: Icon(Icons.search),
                              filled: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    Expanded(
                      child: ListView(
                        key: const Key('settings-navigation-scroll'),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        children: [
                          _sectionLabel('个人'),
                          _navItem(
                            label: '常规',
                            icon: Icons.settings_outlined,
                            selected: _section == '常规',
                          ),
                          _navItem(
                            label: '导入（待开发）',
                            icon: Icons.download_outlined,
                          ),
                          _navItem(
                            label: '外观',
                            icon: Icons.light_mode_outlined,
                            selected: _section == '外观',
                            onTap: () => _select('外观'),
                          ),
                          _navItem(
                            label: '语音（待开发）',
                            icon: Icons.mic_none_outlined,
                          ),
                          _navItem(
                            label: '配置',
                            icon: Icons.shield_outlined,
                            selected: _section == '配置',
                          ),
                          _navItem(
                            label: '个性化（待开发）',
                            icon: Icons.auto_awesome_outlined,
                          ),
                          _navItem(label: '宠物（待开发）', icon: Icons.pets_outlined),
                          _navItem(
                            label: '键盘快捷键',
                            icon: Icons.keyboard_alt_outlined,
                            onTap: () =>
                                SettingsHelpActions.showShortcuts(context),
                          ),
                          _navItem(
                            label: '账户',
                            icon: Icons.account_circle_outlined,
                            trailingArrow: true,
                            onTap: widget.onShowAccount,
                          ),
                          _navItem(
                            label: '关于',
                            icon: Icons.info_outline,
                            onTap: () => SettingsHelpActions.showAbout(context),
                          ),
                          _sectionLabel('集成'),
                          _navItem(
                            label: '电脑操控（待开发）',
                            icon: Icons.auto_awesome_motion_outlined,
                          ),
                          _navItem(
                            label: '应用快照（待开发）',
                            icon: Icons.screenshot_monitor_outlined,
                          ),
                          _navItem(
                            label: '插件',
                            icon: Icons.extension_outlined,
                            selected: _section == '插件',
                            onTap: _selectPlugins,
                          ),
                          _navItem(
                            label: '浏览器',
                            icon: Icons.web_outlined,
                            selected: _section == '浏览器',
                            onTap: _selectBrowser,
                          ),
                          _navItem(
                            label: 'Worktrees',
                            icon: Icons.account_tree_outlined,
                            selected: _section == 'Worktrees',
                            onTap: () => _select('Worktrees'),
                          ),
                          _sectionLabel('编码'),
                          _navItem(
                            label: '钩子',
                            icon: Icons.anchor_outlined,
                            selected: _section == '钩子',
                            onTap: () => _select('钩子'),
                          ),
                          _navItem(
                            label: '连接（待开发）',
                            icon: Icons.language_outlined,
                          ),
                          _navItem(
                            label: 'Git（待开发）',
                            icon: Icons.account_tree_outlined,
                          ),
                          _navItem(
                            label: '环境（待开发）',
                            icon: Icons.computer_outlined,
                          ),
                          _sectionLabel('已归档'),
                          _navItem(
                            label: '已归档的聊天',
                            icon: Icons.archive_outlined,
                            selected: _section == '已归档的聊天',
                            onTap: _selectArchivedChats,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _section == '常规'
                ? _generalContent()
                : _section == '外观'
                ? _appearanceContent()
                : _section == '配置'
                ? _configurationContent()
                : _section == '钩子'
                ? _hooksContent()
                : _section == '插件'
                ? _pluginsContent()
                : _section == '浏览器'
                ? _browserContent()
                : _section == 'Worktrees'
                ? _worktreesContent()
                : _section == '已归档的聊天'
                ? _archivedContent()
                : Center(child: Text('“$_section”设置即将推出')),
          ),
        ],
      ),
    );
  }
}
