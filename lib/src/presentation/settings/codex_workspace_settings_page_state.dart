import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/settings/codex_workspace_settings_page.dart';
import 'package:chatgpt/src/services/dock_icon_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 管理设置页面的局部导航和临时显示偏好。
/// Owns settings-page local navigation and transient display preferences.
class SettingsPageState extends State<SettingsPage> {
  final TextEditingController _search = TextEditingController();
  String _section = '常规';
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
    _uiFontSize.dispose();
    _codeFontSize.dispose();
    super.dispose();
  }

  void _select(String section) => setState(() => _section = section);

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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 22, 12, 24),
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
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: '搜索设置...',
                      prefixIcon: Icon(Icons.search),
                      filled: true,
                      border: InputBorder.none,
                    ),
                  ),
                  _sectionLabel('个人'),
                  _navItem(
                    label: '常规',
                    icon: Icons.settings_outlined,
                    selected: _section == '常规',
                  ),
                  _navItem(label: '导入', icon: Icons.download_outlined),
                  _navItem(
                    label: '外观',
                    icon: Icons.light_mode_outlined,
                    selected: _section == '外观',
                    onTap: () {
                      _select('外观');
                    },
                  ),
                  _navItem(label: '语音', icon: Icons.mic_none_outlined),
                  _navItem(
                    label: '配置',
                    icon: Icons.shield_outlined,
                    onTap: widget.onConfigureRuntime,
                  ),
                  _navItem(label: '个性化', icon: Icons.auto_awesome_outlined),
                  _navItem(label: '宠物', icon: Icons.pets_outlined),
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
                    label: '电脑操控',
                    icon: Icons.auto_awesome_motion_outlined,
                  ),
                  _navItem(
                    label: '应用快照',
                    icon: Icons.screenshot_monitor_outlined,
                  ),
                  _navItem(
                    label: '插件',
                    icon: Icons.extension_outlined,
                    onTap: widget.onShowPlugins,
                  ),
                  _navItem(label: '浏览器', icon: Icons.web_outlined),
                  _sectionLabel('编码'),
                  _navItem(label: '钩子', icon: Icons.anchor_outlined),
                  _navItem(label: '连接', icon: Icons.language_outlined),
                  _navItem(label: 'Git', icon: Icons.account_tree_outlined),
                  _navItem(label: '环境', icon: Icons.computer_outlined),
                  _navItem(label: 'Worktrees', icon: Icons.call_split_outlined),
                  _sectionLabel('已归档'),
                  _navItem(label: '已归档的聊天', icon: Icons.archive_outlined),
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
              : Center(child: Text('“$_section”设置即将推出')),
        ),
      ],
    );
  }
}
