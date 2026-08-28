import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Shows one selected Skill as a compact, inspectable Composer context token.
class ComposerSelectedSkillChip extends StatelessWidget {
  const ComposerSelectedSkillChip({
    super.key,
    required this.skill,
    required this.onOpen,
    required this.onRemove,
  });

  final CodexSkill skill;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      button: true,
      label: '${skill.label}，查看技能详情',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 230),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: palette.controlBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: ValueKey('composer-skill-chip-${skill.name}'),
              borderRadius: BorderRadius.circular(6),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hub_outlined, size: 15, color: palette.active),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        skill.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.active,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              key: ValueKey('composer-skill-remove-${skill.name}'),
              borderRadius: BorderRadius.circular(6),
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(3, 7, 7, 7),
                child: Icon(Icons.close, size: 14, color: palette.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
