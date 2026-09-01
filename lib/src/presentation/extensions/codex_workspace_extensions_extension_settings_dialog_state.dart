// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_dialog.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_tab_button.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_notice.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_list.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_settings_row.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_extension_skill_glyph.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_add_mcp_server_dialog.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_plugin_glyph.dart';

/// 管理扩展设置页签、搜索条件和按需刷新的短生命周期 UI 状态。
/// Owns tab selection, search filtering, and on-demand refresh state for extension settings.
class ExtensionSettingsDialogState extends State<ExtensionSettingsDialog> {
  final TextEditingController _search = TextEditingController();
  ExtensionSettingsTab _tab = ExtensionSettingsTab.plugins;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 切换扩展类别时清空搜索，并只刷新当前选中的数据源。
  /// Switches extension categories, clears search, and refreshes the selected data source.
  void _select(ExtensionSettingsTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _search.clear();
    });
    switch (tab) {
      case ExtensionSettingsTab.plugins:
        unawaited(widget.controller.refreshPlugins());
      case ExtensionSettingsTab.mcp:
        unawaited(widget.controller.refreshMcpServers());
      case ExtensionSettingsTab.skills:
        unawaited(widget.controller.refreshSkills(forceReload: true));
    }
  }

  String get _hint => switch (_tab) {
    ExtensionSettingsTab.plugins => '搜索插件',
    ExtensionSettingsTab.mcp => '搜索 MCP 服务器',
    ExtensionSettingsTab.skills => '搜索技能',
  };

  Future<void> _showAddMcpServer() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AddMcpServerDialog(controller: widget.controller),
    );
  }

  Future<void> _showMcpServer(CodexMcpServer server) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(server.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('连接方式'),
          const SizedBox(height: 6),
          SelectableText(server.transportLabel),
          const SizedBox(height: 18),
          Text('配置范围：${server.scopeLabel}'),
          if (server.configurationPath case final path?) ...[
            const SizedBox(height: 6),
            SelectableText(
              path,
              style: TextStyle(
                fontSize: 12,
                color: YeknomPalette.of(context).muted,
              ),
            ),
          ],
          if (server.authStatus case final status?) ...[
            const SizedBox(height: 18),
            Text('认证状态：$status'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    ),
  );

  Future<void> _removePlugin(CodexPlugin plugin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('remove-plugin-dialog'),
        title: const Text('卸载插件？'),
        content: Text('“${plugin.name}”的连接器授权不会随卸载自动移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            key: const Key('confirm-remove-plugin-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.removePlugin(plugin);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final media = MediaQuery.sizeOf(context);
    final installed = widget.controller.plugins
        .where((plugin) => plugin.installed)
        .toList(growable: false);
    final query = _search.text.trim().toLowerCase();
    final loading = switch (_tab) {
      ExtensionSettingsTab.plugins => widget.controller.pluginsLoading,
      ExtensionSettingsTab.mcp => widget.controller.mcpServersLoading,
      ExtensionSettingsTab.skills => widget.controller.skillsLoading,
    };
    final tabError = switch (_tab) {
      ExtensionSettingsTab.plugins => widget.controller.pluginsError,
      ExtensionSettingsTab.mcp => widget.controller.mcpServersError,
      ExtensionSettingsTab.skills => widget.controller.skillsError,
    };
    final actionError = widget.controller.pluginActionError;
    final warning = widget.controller.pluginActionWarning;

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 18, 18, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final tabs = Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  ExtensionSettingsTabButton(
                    key: const Key('settings-plugins-tab'),
                    label: '插件',
                    count: installed.length,
                    selected: _tab == ExtensionSettingsTab.plugins,
                    onTap: () => _select(ExtensionSettingsTab.plugins),
                  ),
                  ExtensionSettingsTabButton(
                    key: const Key('settings-mcp-tab'),
                    label: 'MCP',
                    count: widget.controller.mcpServers.length,
                    selected: _tab == ExtensionSettingsTab.mcp,
                    onTap: () => _select(ExtensionSettingsTab.mcp),
                  ),
                  ExtensionSettingsTabButton(
                    key: const Key('settings-skills-tab'),
                    label: '技能',
                    count: widget.controller.skills.length,
                    selected: _tab == ExtensionSettingsTab.skills,
                    onTap: () => _select(ExtensionSettingsTab.skills),
                  ),
                ],
              );
              final search = SizedBox(
                width: compact ? constraints.maxWidth : 225,
                height: 38,
                child: TextField(
                  key: const Key('extension-settings-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _hint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: palette.field,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                ),
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [tabs, const SizedBox(height: 12), search],
                    )
                  : Row(
                      children: [
                        Expanded(child: tabs),
                        const SizedBox(width: 16),
                        search,
                      ],
                    );
            },
          ),
        ),
        if (widget.controller.pluginSaving || loading)
          const LinearProgressIndicator(minHeight: 2),
        if (widget.controller.pluginActionProgress case final progress?)
          ExtensionSettingsNotice(
            key: const Key('plugin-action-progress'),
            icon: Icons.sync,
            message: progress,
          )
        else if (actionError != null)
          ExtensionSettingsNotice(
            key: const Key('plugin-action-error'),
            icon: Icons.error_outline,
            message: actionError,
            color: palette.fault,
          )
        else if (warning != null)
          ExtensionSettingsNotice(
            key: const Key('plugin-action-warning'),
            icon: Icons.warning_amber_rounded,
            message: warning,
            color: palette.warning,
          )
        else if (tabError != null)
          ExtensionSettingsNotice(
            key: const Key('plugin-action-error'),
            icon: Icons.error_outline,
            message: tabError,
            color: palette.fault,
          )
        else if (widget.controller.pluginActionResult case final result?)
          ExtensionSettingsNotice(
            key: const Key('plugin-action-result'),
            icon: Icons.restart_alt,
            message: result,
            color: palette.ack,
          ),
        Expanded(
          child: switch (_tab) {
            ExtensionSettingsTab.plugins => _buildPlugins(installed, query),
            ExtensionSettingsTab.mcp => _buildMcp(query),
            ExtensionSettingsTab.skills => _buildSkills(query),
          },
        ),
      ],
    );
    if (widget.embedded) {
      return KeyedSubtree(
        key: const Key('settings-plugins-page'),
        child: content,
      );
    }
    return Dialog(
      key: const Key('plugin-manager-dialog'),
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      child: SizedBox(
        width: math.min(760, media.width - 48),
        height: math.min(620, media.height - 48),
        child: content,
      ),
    );
  }

  Widget _buildPlugins(List<CodexPlugin> installed, String query) {
    final rows = installed
        .where(
          (plugin) =>
              query.isEmpty ||
              plugin.name.toLowerCase().contains(query) ||
              (plugin.description ?? '').toLowerCase().contains(query),
        )
        .toList(growable: false);
    return ExtensionSettingsList(
      emptyMessage: installed.isEmpty ? '尚未安装插件。' : '没有匹配的插件。',
      header: Row(
        children: [
          TextButton.icon(
            onPressed: widget.controller.pluginSaving
                ? null
                : widget.onAddMarketplace,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加插件市场'),
          ),
          TextButton(
            onPressed: widget.controller.pluginSaving
                ? null
                : widget.onManageMarketplaces,
            child: const Text('管理市场'),
          ),
        ],
      ),
      children: rows
          .map(
            (plugin) => ExtensionSettingsRow(
              key: ValueKey('settings-plugin-${plugin.id}'),
              leading: PluginGlyph(
                name: plugin.title,
                active: plugin.enabled,
                logoPath: plugin.logoPath,
              ),
              title: plugin.title,
              subtitle: plugin.description?.trim().isNotEmpty == true
                  ? plugin.description!.trim()
                  : plugin.summary,
              enabled: plugin.enabled,
              busy: widget.controller.pluginSaving,
              active: widget.controller.pluginActionTargetId == plugin.id,
              auxiliary: IconButton(
                key: ValueKey('remove-plugin-${plugin.id}'),
                tooltip: '卸载插件',
                onPressed: widget.controller.pluginSaving
                    ? null
                    : () => _removePlugin(plugin),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
              onChanged: (enabled) =>
                  widget.controller.setPluginEnabled(plugin, enabled),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildMcp(String query) {
    final servers = widget.controller.mcpServers
        .where(
          (server) =>
              query.isEmpty ||
              server.name.toLowerCase().contains(query) ||
              server.transportLabel.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return ExtensionSettingsList(
      emptyMessage: widget.controller.mcpServers.isEmpty
          ? '尚未配置 MCP 服务器。'
          : '没有匹配的 MCP 服务器。',
      header: Row(
        children: [
          const Expanded(
            child: Text(
              '服务器',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton.tonalIcon(
            key: const Key('add-mcp-server-button'),
            onPressed: widget.controller.pluginSaving
                ? null
                : _showAddMcpServer,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加服务器'),
          ),
        ],
      ),
      grouped: true,
      children: servers
          .map(
            (server) => ExtensionSettingsRow(
              key: ValueKey('settings-mcp-${server.name}'),
              title: server.name,
              meta: server.scopeLabel,
              enabled: server.enabled,
              busy: widget.controller.pluginSaving,
              active: widget.controller.pluginActionTargetId == server.name,
              compact: true,
              auxiliary: IconButton(
                tooltip: '服务器详情',
                onPressed: () => _showMcpServer(server),
                icon: const Icon(Icons.settings_outlined, size: 18),
              ),
              onChanged: server.canChangeEnabled
                  ? (enabled) =>
                        widget.controller.setMcpServerEnabled(server, enabled)
                  : null,
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildSkills(String query) {
    final skills = widget.controller.skills
        .where(
          (skill) =>
              query.isEmpty ||
              skill.name.toLowerCase().contains(query) ||
              skill.label.toLowerCase().contains(query) ||
              skill.summary.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return ExtensionSettingsList(
      emptyMessage: widget.controller.skills.isEmpty
          ? '当前项目没有可用技能。'
          : '没有匹配的技能。',
      children: skills
          .map(
            (skill) => ExtensionSettingsRow(
              key: ValueKey('settings-skill-${skill.path}'),
              leading: const ExtensionSkillGlyph(),
              title: skill.label,
              subtitle: skill.summary,
              meta: skill.scope.toLowerCase() == 'system' ? '系统' : '个人',
              enabled: skill.enabled,
              busy: widget.controller.pluginSaving,
              active: widget.controller.pluginActionTargetId == skill.path,
              onChanged: (enabled) =>
                  widget.controller.setSkillEnabled(skill, enabled),
            ),
          )
          .toList(growable: false),
    );
  }
}
