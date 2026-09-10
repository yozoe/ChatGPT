import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/domain/codex_file_search_result.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_slash_command.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Displays the keyboard-navigable skill or command picker above the Composer.
class ComposerSlashCommandMenu extends StatelessWidget {
  const ComposerSlashCommandMenu({
    super.key,
    required this.commands,
    required this.skills,
    required this.files,
    required this.showSkills,
    required this.skillsLoading,
    required this.skillsError,
    required this.filesLoading,
    required this.filesError,
    required this.searchQuery,
    required this.commandScrollKeys,
    required this.skillScrollKeys,
    required this.fileScrollKeys,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSkillSelected,
    required this.onFileSelected,
    required this.onItemHovered,
    this.menuKey = const Key('composer-slash-menu'),
    this.semanticLabel,
    this.commandSectionLabel = '快捷指令',
    this.skillSectionLabel = '技能',
    this.showSkillScope = true,
    this.emptyResultLabel,
  });

  final List<ComposerSlashCommand> commands;
  final List<CodexSkill> skills;
  final List<CodexFileSearchResult> files;
  final bool showSkills;
  final bool skillsLoading;
  final String? skillsError;
  final bool filesLoading;
  final String? filesError;
  final String searchQuery;
  final Map<ComposerSlashCommandKind, GlobalKey> commandScrollKeys;
  final Map<String, GlobalKey> skillScrollKeys;
  final Map<String, GlobalKey> fileScrollKeys;
  final int selectedIndex;
  final ValueChanged<ComposerSlashCommand> onSelected;
  final ValueChanged<CodexSkill> onSkillSelected;
  final ValueChanged<CodexFileSearchResult> onFileSelected;
  final ValueChanged<int> onItemHovered;
  final Key menuKey;
  final String? semanticLabel;
  final String commandSectionLabel;
  final String skillSectionLabel;
  final bool showSkillScope;
  final String? emptyResultLabel;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      container: true,
      label: semanticLabel ?? (showSkills ? '添加上下文与插件' : '快捷指令'),
      child: Material(
        key: menuKey,
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: palette.field,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.controlBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: showSkills
              ? _buildSkills(context, palette)
              : commands.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '没有匹配的快捷指令',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.muted),
                  ),
                )
              : _buildCommandList(context, palette),
        ),
      ),
    );
  }

  Widget _buildSkills(BuildContext context, YeknomPalette palette) {
    final hasSearchQuery = searchQuery.trim().isNotEmpty;
    if (!skillsLoading &&
        skillsError == null &&
        hasSearchQuery &&
        commands.isEmpty &&
        files.isEmpty &&
        !filesLoading &&
        filesError == null &&
        skills.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          emptyResultLabel ?? '没有匹配的技能或快捷指令',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.muted),
        ),
      );
    }
    return SingleChildScrollView(
      key: const Key('composer-slash-skill-list'),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          if (commands.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 5),
              child: Text(
                commandSectionLabel,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ),
          for (var index = 0; index < commands.length; index++)
            _buildCommandRow(context, palette, commands[index], index),
          if (commands.isNotEmpty &&
              (files.isNotEmpty ||
                  filesLoading ||
                  filesError != null ||
                  skills.isNotEmpty ||
                  skillsLoading))
            const SizedBox(height: 5),
          if (files.isNotEmpty || filesLoading || filesError != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 5),
              child: Text(
                '文件',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ),
            if (filesLoading && files.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (filesError != null && files.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Text(
                  filesError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.fault),
                ),
              )
            else
              for (var index = 0; index < files.length; index++)
                _buildFileRow(
                  context,
                  palette,
                  files[index],
                  commands.length + index,
                ),
            if (skills.isNotEmpty || skillsLoading) const SizedBox(height: 5),
          ],
          if (skills.isNotEmpty || skillsLoading || !hasSearchQuery)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 5),
              child: Text(
                skillSectionLabel,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ),
          if (skillsLoading && skills.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (skills.isEmpty && !hasSearchQuery)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Text(
                skillsError ?? '当前项目没有可用技能',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: skillsError == null ? palette.muted : palette.fault,
                ),
              ),
            )
          else
            for (var index = 0; index < skills.length; index++)
              _buildSkillRow(
                context,
                palette,
                skills[index],
                commands.length + files.length + index,
              ),
        ],
      ),
    );
  }

  Widget _buildCommandList(BuildContext context, YeknomPalette palette) {
    return SingleChildScrollView(
      key: const Key('composer-slash-command-list'),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < commands.length; index++)
            _buildCommandRow(context, palette, commands[index], index),
        ],
      ),
    );
  }

  Widget _buildSkillRow(
    BuildContext context,
    YeknomPalette palette,
    CodexSkill skill,
    int index,
  ) {
    final selected = index == selectedIndex;
    return KeyedSubtree(
      key: skillScrollKeys[skill.path],
      child: Semantics(
        button: true,
        selected: selected,
        label: '${skill.label}，${skill.summary}，${_scopeLabel(skill.scope)}',
        child: InkWell(
          key: ValueKey('composer-slash-skill-${skill.name}'),
          borderRadius: BorderRadius.circular(10),
          onHover: (hovering) {
            if (hovering) onItemHovered(index);
          },
          onTap: () => onSkillSelected(skill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? palette.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  _skillIcon(skill.name),
                  size: 16,
                  color: selected ? palette.trace : palette.muted,
                ),
                const SizedBox(width: 9),
                Flexible(
                  flex: 2,
                  child: Text(
                    skill.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.trace, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    skill.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ),
                if (showSkillScope) ...[
                  const SizedBox(width: 8),
                  Text(
                    _scopeLabel(skill.scope),
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileRow(
    BuildContext context,
    YeknomPalette palette,
    CodexFileSearchResult file,
    int index,
  ) {
    final selected = index == selectedIndex;
    final relativePath = file.path.startsWith(file.root)
        ? file.path
              .substring(file.root.length)
              .replaceFirst(RegExp(r'^[/\\]'), '')
        : file.path;
    final lastSeparator = relativePath.lastIndexOf(RegExp(r'[/\\]'));
    final locationLabel = lastSeparator > 0
        ? relativePath.substring(0, lastSeparator)
        : file.root;
    final identity = '${file.root}\u0000${file.path}';
    return KeyedSubtree(
      key: fileScrollKeys[identity],
      child: Semantics(
        button: true,
        selected: selected,
        label: '${file.fileName}，$relativePath',
        child: InkWell(
          key: ValueKey('composer-file-search-result-$identity'),
          borderRadius: BorderRadius.circular(10),
          onHover: (hovering) {
            if (hovering) onItemHovered(index);
          },
          onTap: () => onFileSelected(file),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? palette.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  file.isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: selected ? palette.trace : palette.muted,
                ),
                const SizedBox(width: 9),
                Flexible(
                  flex: 2,
                  child: Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.trace, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommandRow(
    BuildContext context,
    YeknomPalette palette,
    ComposerSlashCommand command,
    int index,
  ) {
    final selected = index == selectedIndex;
    return KeyedSubtree(
      key: commandScrollKeys[command.kind],
      child: Semantics(
        button: true,
        enabled: command.enabled,
        selected: selected && command.enabled,
        label: '${command.label}，${command.description}',
        child: InkWell(
          key: ValueKey('composer-slash-command-${command.kind.name}'),
          borderRadius: BorderRadius.circular(12),
          onHover: command.enabled
              ? (hovering) {
                  if (hovering) onItemHovered(index);
                }
              : null,
          onTap: command.enabled ? () => onSelected(command) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: selected && command.enabled
                  ? palette.raised
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  command.icon,
                  size: 18,
                  color: command.enabled
                      ? selected
                            ? palette.trace
                            : palette.muted
                      : palette.muted.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 10),
                Flexible(
                  flex: 2,
                  child: Text(
                    command.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: command.enabled
                          ? palette.trace
                          : palette.muted.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  flex: 3,
                  child: Text(
                    command.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: command.enabled
                          ? palette.muted
                          : palette.muted.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _scopeLabel(String scope) => switch (scope.toLowerCase()) {
    'user' || 'personal' => '个人',
    'project' => '项目',
    'system' => '系统',
    _ => scope,
  };

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
}
