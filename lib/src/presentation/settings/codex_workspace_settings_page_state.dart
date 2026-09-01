import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_page.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_dialog.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/services/dock_icon_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  String _defaultEditor = 'VS Code';
  bool _showInMenuBar = true;
  bool _showBottomPanel = true;
  String _terminalPosition = '底部';
  bool _preventSleep = false;
  bool _promptSuggestions = false;
  bool _usePointerCursor = false;
  String _reduceMotion = '系统';
  String _diffMarkers = '颜色';
  bool _fontSmoothing = true;
  int _dockIcon = 0;
  final DockIconService _dockIconService = DockIconService();
  final TextEditingController _uiFontSize = TextEditingController(text: '14');
  final TextEditingController _codeFontSize = TextEditingController(text: '13');

  @override
  void initState() {
    super.initState();
    _restoreDockIconSelection();
  }

  @override
  void dispose() {
    _search.dispose();
    _archiveSearch.dispose();
    _uiFontSize.dispose();
    _codeFontSize.dispose();
    super.dispose();
  }

  void _select(String section) => setState(() => _section = section);

  void _selectArchivedChats() {
    setState(() {
      _section = '已归档的聊天';
      _archiveSearch.clear();
    });
    unawaited(widget.controller.refreshArchivedThreads());
  }

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

  /// 打开实验性内置浏览器，保留设置导航和其余页面状态。
  /// Opens the experimental embedded browser while retaining settings navigation and other page state.
  void _selectBrowser() => _select('浏览器');

  /// 构建实验性内置浏览器的设置工作区内容。
  /// Builds the settings-workspace content for the experimental embedded browser.
  Widget _browserContent() => const BrowserWorkspacePage();

  Widget _pluginsContent() => LayoutBuilder(
    builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth < 620 ? 24.0 : 72.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          46,
          horizontalPadding,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '插件',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '管理已安装插件、MCP 服务器和可用技能。',
              style: TextStyle(color: YeknomPalette.of(context).muted),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ExtensionSettingsDialog(
                embedded: true,
                controller: widget.controller,
                onAddMarketplace: widget.onAddMarketplace,
                onManageMarketplaces: widget.onManageMarketplaces,
              ),
            ),
          ],
        ),
      );
    },
  );

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

  Future<void> _showShortcuts() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('settings-shortcuts-dialog'),
        title: const Text('键盘快捷键'),
        content: const SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.add_comment_outlined),
                title: Text('新对话'),
                trailing: Text('⌘ N'),
              ),
              ListTile(
                leading: Icon(Icons.search_outlined),
                title: Text('搜索聊天'),
                trailing: Text('⌘ K'),
              ),
              ListTile(
                leading: Icon(Icons.stop_circle_outlined),
                title: Text('停止当前任务'),
                trailing: Text('Esc'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Codex Desk',
      applicationVersion: '1.0.0',
      applicationLegalese: '本地优先 · stdio JSON-RPC',
    );
  }

  Widget _navItem({
    required String label,
    required IconData icon,
    bool selected = false,
    VoidCallback? onTap,
    bool trailingArrow = false,
  }) {
    final palette = YeknomPalette.of(context);
    return InkWell(
      key: Key('settings-nav-$label'),
      onTap: onTap ?? () => _select(label),
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
            Icon(icon, size: 18, color: palette.trace),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            if (trailingArrow)
              Icon(Icons.arrow_outward, size: 16, color: palette.muted),
          ],
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
                      Align(alignment: Alignment.centerLeft, child: trailing),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: details),
                    if (trailing != null) ...[
                      const SizedBox(width: 24),
                      trailing,
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
                      title: '默认文件打开位置',
                      description: '默认打开文件和文件夹的位置。',
                      trailing: PopupMenuButton<String>(
                        key: const Key('settings-default-editor'),
                        initialValue: _defaultEditor,
                        onSelected: (value) =>
                            setState(() => _defaultEditor = value),
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
                      title: '在菜单栏中显示',
                      description: '关闭主窗口后，仍在 macOS 菜单栏中保留 Codex Desk',
                      trailing: Switch(
                        value: _showInMenuBar,
                        onChanged: (value) =>
                            setState(() => _showInMenuBar = value),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '底部面板',
                      description: '在应用标题栏中显示底部面板控件',
                      trailing: Switch(
                        value: _showBottomPanel,
                        onChanged: (value) =>
                            setState(() => _showBottomPanel = value),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '默认终端位置',
                      description: '选择终端快捷键和环境操作在何处打开终端标签页',
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '底部', label: Text('底部')),
                          ButtonSegment(value: '右侧', label: Text('右侧')),
                        ],
                        selected: {_terminalPosition},
                        onSelectionChanged: (selection) =>
                            setState(() => _terminalPosition = selection.first),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '运行时防止系统休眠',
                      description: '在 Codex Desk 运行任务时，让电脑保持唤醒状态',
                      trailing: Switch(
                        value: _preventSleep,
                        onChanged: (value) =>
                            setState(() => _preventSleep = value),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '提示词建议',
                      description: '通过搜索项目文件和已连接的应用，建议下一步操作',
                      trailing: Switch(
                        value: _promptSuggestions,
                        onChanged: (value) =>
                            setState(() => _promptSuggestions = value),
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

  Widget _dockIconTile({required int index, required String label}) {
    final palette = YeknomPalette.of(context);
    final selected = _dockIcon == index;
    return Semantics(
      label: 'Dock 图标：$label',
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('settings-dock-icon-$index'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => _selectDockIcon(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? palette.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? palette.trace : palette.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: index == 0
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: SvgPicture.asset(
                      'assets/branding/codex-desk-icon-traced-light.svg',
                      fit: BoxFit.contain,
                    ),
                  )
                : Image.asset('icon.png', fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Widget _appearanceContent() {
    final palette = YeknomPalette.of(context);
    final heading = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontSize: 38,
      fontWeight: FontWeight.w500,
    );
    return ListView(
      key: const Key('settings-appearance-page'),
      padding: const EdgeInsets.fromLTRB(58, 26, 58, 58),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('偏好设置', style: heading),
              const SizedBox(height: 32),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    _settingRow(
                      title: '使用指针光标',
                      description: '悬停交互元素时切换为指针光标',
                      trailing: Switch(
                        value: _usePointerCursor,
                        onChanged: (value) =>
                            setState(() => _usePointerCursor = value),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: 'Dock 图标',
                      description: '选择应用在 Dock 中使用的图标',
                      trailing: Wrap(
                        spacing: 12,
                        children: [
                          _dockIconTile(index: 0, label: '结绳'),
                          _dockIconTile(index: 1, label: '命令云'),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '减少动态效果',
                      description: '减少动画效果或匹配系统设置',
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '系统', label: Text('系统')),
                          ButtonSegment(value: '开启', label: Text('开启')),
                          ButtonSegment(value: '关闭', label: Text('关闭')),
                        ],
                        selected: {_reduceMotion},
                        onSelectionChanged: (selection) =>
                            setState(() => _reduceMotion = selection.first),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: 'UI 字号',
                      description: '调整 ChatGPT 界面使用的基准字号',
                      trailing: _fontField(_uiFontSize),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '代码字体大小',
                      description: '调整聊天和差异视图中代码使用的基础字号',
                      trailing: _fontField(_codeFontSize),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '差异标记',
                      description: '使用颜色或 +/- 标记显示更改',
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '颜色', label: Text('颜色')),
                          ButtonSegment(value: '+/-', label: Text('+/-')),
                        ],
                        selected: {_diffMarkers},
                        onSelectionChanged: (selection) =>
                            setState(() => _diffMarkers = selection.first),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    _settingRow(
                      title: '字体平滑',
                      description: '使用 macOS 原生字体抗锯齿',
                      trailing: Switch(
                        value: _fontSmoothing,
                        onChanged: (value) =>
                            setState(() => _fontSmoothing = value),
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

  Widget _fontField(TextEditingController controller) => SizedBox(
    width: 128,
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: const InputDecoration(suffixText: 'px'),
    ),
  );

  Widget _configurationContent() {
    final palette = YeknomPalette.of(context);
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
                          title: '批准策略',
                          description: '选择 Codex 何时请求你批准操作。此偏好会保存并用于后续任务。',
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
                          title: '沙盒设置',
                          description:
                              '文件与命令的实际访问范围由 Codex App Server 和项目权限决定。',
                          trailing: Text(
                            '由配置管理',
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '网页搜索',
                          description: '网络访问能力由当前 Codex 运行时及其配置决定。',
                          trailing: Text(
                            '由配置管理',
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '输出详细程度',
                          description: '回复风格由所选模型和 Codex 配置决定；本应用不会覆盖它。',
                          trailing: Text(
                            '模型默认',
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                        Divider(height: 1, color: palette.border),
                        _settingRow(
                          title: '推理摘要',
                          description: '是否提供摘要由模型和运行时能力协商，本应用会原样显示可用结果。',
                          trailing: Text(
                            '自动',
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
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
        InkWell(
          key: Key('settings-hook-${hook.key}'),
          onTap: () => _showHooks(hooks),
          borderRadius: BorderRadius.circular(16),
          child: _hookTile(hook),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );

  Widget _hookTile(CodexHook hook) {
    final palette = YeknomPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: ListTile(
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

  Widget _archivedThreadRow(CodexThread thread, CodexController controller) {
    final palette = YeknomPalette.of(context);
    final updating = controller.isUpdatingThread(thread.id);
    final restoring = controller.isUnarchivingThread(thread.id);
    final enabled = controller.status == RuntimeStatus.ready && !updating;
    final canDelete = enabled && !controller.hasRunningTasks;
    return Container(
      key: Key('settings-archived-thread-${thread.id}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  _archiveDate(thread),
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (updating || restoring)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              key: Key('settings-archived-delete-${thread.id}'),
              tooltip: '永久删除',
              onPressed: canDelete ? () => _deleteArchivedThread(thread) : null,
              icon: const Icon(Icons.delete_outline, size: 17),
            ),
            TextButton(
              key: Key('settings-archived-unarchive-${thread.id}'),
              onPressed: enabled
                  ? () => controller.unarchiveThread(thread)
                  : null,
              child: const Text('取消归档'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _archivedContent() {
    final palette = YeknomPalette.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final query = _archiveSearch.text.trim().toLowerCase();
        final projectName = _archiveProjectName();
        final threads = controller.archivedThreads
            .where((thread) {
              final matchesQuery =
                  query.isEmpty ||
                  '${thread.title} ${thread.preview}'.toLowerCase().contains(
                    query,
                  );
              final matchesProject = _archiveProjectFilter == '当前项目';
              return matchesQuery && matchesProject;
            })
            .toList(growable: false);
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            return ListView(
              key: const Key('settings-archived-chats-page'),
              padding: EdgeInsets.fromLTRB(
                compact ? 24 : 72,
                46,
                compact ? 24 : 72,
                72,
              ),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                '已归档的聊天',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                            TextButton.icon(
                              key: const Key('settings-archived-delete-all'),
                              onPressed:
                                  controller.archivedThreads.isEmpty ||
                                      controller.status !=
                                          RuntimeStatus.ready ||
                                      controller.hasRunningTasks
                                  ? null
                                  : _deleteAllArchivedThreads,
                              icon: const Icon(Icons.delete_outline, size: 15),
                              label: const Text('全部删除'),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 34),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: compact ? constraints.maxWidth : 330,
                              height: 40,
                              child: TextField(
                                key: const Key('settings-archived-search'),
                                controller: _archiveSearch,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  hintText: '搜索已归档聊天',
                                  prefixIcon: Icon(Icons.search, size: 17),
                                  prefixIconConstraints: BoxConstraints(
                                    minWidth: 38,
                                    maxWidth: 38,
                                    minHeight: 40,
                                    maxHeight: 40,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              key: const Key('settings-archived-type-filter'),
                              initialValue: _archiveTypeFilter,
                              onSelected: (value) =>
                                  setState(() => _archiveTypeFilter = value),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: '全部聊天',
                                  child: Text('全部聊天'),
                                ),
                              ],
                              child: Chip(
                                avatar: const Icon(Icons.tune, size: 15),
                                label: Text(_archiveTypeFilter),
                              ),
                            ),
                            PopupMenuButton<String>(
                              key: const Key(
                                'settings-archived-project-filter',
                              ),
                              initialValue: _archiveProjectFilter,
                              onSelected: (value) =>
                                  setState(() => _archiveProjectFilter = value),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: '当前项目',
                                  child: Text('当前项目'),
                                ),
                              ],
                              child: Chip(
                                avatar: const Icon(
                                  Icons.folder_outlined,
                                  size: 15,
                                ),
                                label: Text(_archiveProjectFilter),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        if (controller.archivedThreadsLoading)
                          const Center(child: CircularProgressIndicator())
                        else if (controller.archivedThreadsError
                            case final error?)
                          _hooksMessage(
                            key: const Key('settings-archived-error-state'),
                            title: '无法读取已归档聊天',
                            detail: error,
                          )
                        else if (threads.isEmpty)
                          _hooksMessage(
                            key: const Key('settings-archived-empty-state'),
                            title: query.isEmpty ? '暂无已归档聊天' : '未找到匹配的聊天',
                            detail: query.isEmpty
                                ? '归档的聊天会显示在这里。'
                                : '请尝试其他搜索词。',
                          )
                        else
                          DecoratedBox(
                            key: const Key('settings-archived-list'),
                            decoration: BoxDecoration(
                              color: palette.raised,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: palette.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    14,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.folder_outlined,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(projectName)),
                                      Text(
                                        '${threads.length} 个聊天',
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.more_horiz, size: 17),
                                    ],
                                  ),
                                ),
                                for (final thread in threads)
                                  _archivedThreadRow(thread, controller),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Row(
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
                          onTap: _showShortcuts,
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
                          onTap: _showAbout,
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
                        _navItem(
                          label: 'Worktrees（待开发）',
                          icon: Icons.call_split_outlined,
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
              : _section == '已归档的聊天'
              ? _archivedContent()
              : Center(child: Text('“$_section”设置即将推出')),
        ),
      ],
    );
  }
}
