import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Displays the metadata and instruction file for a selected Composer Skill.
class ComposerSkillDetailsDialog extends StatelessWidget {
  const ComposerSkillDetailsDialog({
    super.key,
    required this.skill,
    required this.content,
  });

  final CodexSkill skill;
  final Future<String> content;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Dialog(
      key: const Key('composer-skill-details-dialog'),
      backgroundColor: palette.module,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.controlBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.hub_outlined, size: 18, color: palette.active),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      skill.label,
                      style: TextStyle(
                        color: palette.trace,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('composer-skill-details-close'),
                    tooltip: '关闭技能详情',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: 18, color: palette.muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                skill.description.isEmpty ? skill.summary : skill.description,
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 5,
                children: [
                  _detailLabel(palette, _scopeLabel(skill.scope)),
                  _detailLabel(palette, skill.path),
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: palette.border),
              const SizedBox(height: 12),
              Text(
                '技能内容',
                style: TextStyle(
                  color: palette.trace,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              FutureBuilder<String>(
                future: content,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return SelectableText(
                      '无法读取此技能的内容：${snapshot.error}',
                      style: TextStyle(color: palette.fault, fontSize: 12),
                    );
                  }
                  return SelectableText(
                    snapshot.data ?? '',
                    style: TextStyle(
                      color: palette.trace,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailLabel(YeknomPalette palette, String text) => Container(
    constraints: const BoxConstraints(maxWidth: 560),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: palette.field,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: palette.border),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: palette.muted, fontSize: 11),
    ),
  );

  String _scopeLabel(String scope) => switch (scope.toLowerCase()) {
    'user' || 'personal' => '个人技能',
    'project' => '项目技能',
    'system' => '系统技能',
    _ => scope,
  };
}
