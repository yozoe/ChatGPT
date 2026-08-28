import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_slash_command.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Displays the keyboard-navigable skill or command picker above the Composer.
class ComposerSlashCommandMenu extends StatelessWidget {
  const ComposerSlashCommandMenu({
    super.key,
    required this.commands,
    required this.skills,
    required this.showSkills,
    required this.skillsLoading,
    required this.skillsError,
    required this.commandScrollKeys,
    required this.skillScrollKeys,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSkillSelected,
  });

  final List<ComposerSlashCommand> commands;
  final List<CodexSkill> skills;
  final bool showSkills;
  final bool skillsLoading;
  final String? skillsError;
  final Map<ComposerSlashCommandKind, GlobalKey> commandScrollKeys;
  final Map<String, GlobalKey> skillScrollKeys;
  final int selectedIndex;
  final ValueChanged<ComposerSlashCommand> onSelected;
  final ValueChanged<CodexSkill> onSkillSelected;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      container: true,
      label: showSkills ? '技能与快捷指令' : '快捷指令',
      child: Material(
        key: const Key('composer-slash-menu'),
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
    return SingleChildScrollView(
      key: const Key('composer-slash-skill-list'),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 4, 9, 5),
            child: Text(
              '快捷指令',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ),
          for (var index = 0; index < commands.length; index++)
            _buildCommandRow(context, palette, commands[index], index),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 4, 9, 5),
            child: Text(
              '技能',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ),
          if (skillsLoading && skills.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (skills.isEmpty)
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
                commands.length + index,
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
          onTap: () => onSkillSelected(skill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? palette.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.hub_outlined,
                  size: 16,
                  color: selected ? palette.trace : palette.muted,
                ),
                const SizedBox(width: 9),
                SizedBox(
                  width: 138,
                  child: Text(
                    skill.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.trace, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    skill.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _scopeLabel(skill.scope),
                  style: TextStyle(color: palette.muted, fontSize: 12),
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
        selected: selected,
        label: '${command.label}，${command.description}',
        child: InkWell(
          key: ValueKey('composer-slash-command-${command.kind.name}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSelected(command),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? palette.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  command.icon,
                  size: 18,
                  color: selected ? palette.trace : palette.muted,
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 96,
                  child: Text(
                    command.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.trace,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    command.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.muted),
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
}
