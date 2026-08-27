// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugins_page.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_skills_library_page.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_installed_plugin_chip.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugin_library_row.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_library_top_bar.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_library_tab_button.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugin_add_menu.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_library_section_header.dart';

class PluginsPageState extends State<PluginsPage> {
  final TextEditingController _search = TextEditingController();
  bool _personalOnly = false;
  PluginLibraryTab _tab = PluginLibraryTab.plugins;

  void _selectTab(PluginLibraryTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (tab == PluginLibraryTab.skills) {
      unawaited(widget.controller.refreshSkills());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final query = _search.text.trim().toLowerCase();
    final plugins = widget.controller.plugins
        .where((plugin) {
          if (_personalOnly && plugin.marketplaceName.isNotEmpty) return false;
          return query.isEmpty ||
              plugin.name.toLowerCase().contains(query) ||
              plugin.sourceLabel.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final installed = plugins.where((plugin) => plugin.installed).toList();
    final available = plugins.where((plugin) => !plugin.installed).toList();
    return Column(
      children: [
        LibraryTopBar(
          createLabel: '添加',
          onCreate: () => widget.onAddMarketplace(),
          leading: [
            LibraryTabButton(
              key: const Key('plugins-tab'),
              label: '插件',
              selected: _tab == PluginLibraryTab.plugins,
              onTap: () => _selectTab(PluginLibraryTab.plugins),
            ),
            LibraryTabButton(
              key: const Key('plugins-skills-tab'),
              label: '技能',
              selected: _tab == PluginLibraryTab.skills,
              onTap: () => _selectTab(PluginLibraryTab.skills),
            ),
          ],
          createControl: PluginAddMenu(
            onCreatePlugin: widget.onCreatePlugin,
            onAddMarketplace: widget.onAddMarketplace,
            onRecordSkill: widget.onRecordSkill,
          ),
          actions: [
            IconButton(
              key: const Key('plugins-page-refresh'),
              tooltip: _tab == PluginLibraryTab.plugins ? '刷新插件' : '刷新技能',
              onPressed:
                  widget.controller.pluginsLoading ||
                      widget.controller.pluginSaving
                  ? null
                  : _tab == PluginLibraryTab.plugins
                  ? widget.controller.refreshPlugins
                  : widget.controller.refreshSkills,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              key: const Key('plugins-settings-button'),
              tooltip: '插件设置',
              onPressed: widget.controller.pluginSaving
                  ? null
                  : () => widget.onOpenSettings(),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const Divider(height: 1),
        if (_tab == PluginLibraryTab.skills)
          Expanded(
            child: SkillsLibraryPage(
              controller: widget.controller,
              search: _search,
              onChanged: () => setState(() {}),
            ),
          )
        else
          Expanded(
            child: ListView(
              key: const Key('plugins-page'),
              padding: const EdgeInsets.fromLTRB(72, 42, 72, 64),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1036),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '插件',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontSize: 38,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -1,
                            ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '在你常用的工具中使用 Codex',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: palette.muted,
                              fontWeight: FontWeight.w400,
                            ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        key: const Key('plugins-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索插件',
                          prefixIcon: const Icon(Icons.search_outlined),
                          filled: true,
                          fillColor: palette.field,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 42),
                      LibrarySectionHeader(label: '已安装'),
                      const SizedBox(height: 14),
                      installed.isEmpty
                          ? Text(
                              '尚未安装插件。添加 marketplace 后可在此安装和管理插件。',
                              style: TextStyle(color: palette.muted),
                            )
                          : Wrap(
                              spacing: 18,
                              runSpacing: 18,
                              children: installed
                                  .map(
                                    (plugin) =>
                                        InstalledPluginChip(plugin: plugin),
                                  )
                                  .toList(growable: false),
                            ),
                      const SizedBox(height: 34),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('公开'),
                            selected: !_personalOnly,
                            onSelected: (_) =>
                                setState(() => _personalOnly = false),
                          ),
                          ChoiceChip(
                            label: const Text('个人'),
                            selected: _personalOnly,
                            onSelected: (_) =>
                                setState(() => _personalOnly = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 42),
                      LibrarySectionHeader(label: '精选'),
                      const SizedBox(height: 18),
                      if (widget.controller.pluginsLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (available.isEmpty)
                        Text(
                          '没有可安装的插件。使用右上角“添加”连接一个插件市场。',
                          style: TextStyle(color: palette.muted),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 700;
                            return Wrap(
                              spacing: 28,
                              runSpacing: 4,
                              children: available
                                  .map(
                                    (plugin) => SizedBox(
                                      width: twoColumns
                                          ? (constraints.maxWidth - 28) / 2
                                          : constraints.maxWidth,
                                      child: PluginLibraryRow(
                                        plugin: plugin,
                                        busy: widget.controller.pluginSaving,
                                        onInstall: () => widget.controller
                                            .installPlugin(plugin),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            );
                          },
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
}
