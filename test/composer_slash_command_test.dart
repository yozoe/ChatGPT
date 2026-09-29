import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_slash_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches canonical English command aliases', () {
    const command = ComposerSlashCommand(
      kind: ComposerSlashCommandKind.planMode,
      label: '计划模式',
      description: '为多步骤任务制定计划',
      icon: Icons.lightbulb_outline,
      aliases: ['plan'],
    );

    expect(command.matches('plan'), isTrue);
    expect(command.matches('计划'), isTrue);
    expect(command.matches('unknown'), isFalse);
  });

  test('keeps command exposure explicit per Composer surface', () {
    const command = ComposerSlashCommand(
      kind: ComposerSlashCommandKind.goal,
      label: '目标',
      description: '设置持续目标',
      icon: Icons.track_changes_outlined,
      surfaces: {
        ComposerMenuSurface.slash,
        ComposerMenuSurface.mention,
        ComposerMenuSurface.add,
      },
    );
    const slashOnly = ComposerSlashCommand(
      kind: ComposerSlashCommandKind.model,
      label: '模型',
      description: '选择模型',
      icon: Icons.view_in_ar_outlined,
    );

    expect(command.supports(ComposerMenuSurface.slash), isTrue);
    expect(command.supports(ComposerMenuSurface.mention), isTrue);
    expect(command.supports(ComposerMenuSurface.add), isTrue);
    expect(slashOnly.supports(ComposerMenuSurface.slash), isTrue);
    expect(slashOnly.supports(ComposerMenuSurface.mention), isFalse);
    expect(slashOnly.supports(ComposerMenuSurface.add), isFalse);
  });
}
