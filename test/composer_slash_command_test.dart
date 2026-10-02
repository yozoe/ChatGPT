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

  test('uses shared per-surface order without duplicating menu lists', () {
    const commands = [
      ComposerSlashCommand(
        kind: ComposerSlashCommandKind.goal,
        label: '目标',
        description: '',
        icon: Icons.track_changes_outlined,
        surfaces: {
          ComposerMenuSurface.slash,
          ComposerMenuSurface.mention,
          ComposerMenuSurface.add,
        },
        surfaceOrder: {
          ComposerMenuSurface.slash: 2,
          ComposerMenuSurface.mention: 1,
          ComposerMenuSurface.add: 0,
        },
      ),
      ComposerSlashCommand(
        kind: ComposerSlashCommandKind.files,
        label: '文件和文件夹',
        description: '',
        icon: Icons.attach_file,
        surfaces: {ComposerMenuSurface.mention, ComposerMenuSurface.add},
        surfaceOrder: {
          ComposerMenuSurface.mention: 0,
          ComposerMenuSurface.add: 1,
        },
      ),
      ComposerSlashCommand(
        kind: ComposerSlashCommandKind.mcpStatus,
        label: 'MCP',
        description: '',
        icon: Icons.hub_outlined,
        surfaceOrder: {ComposerMenuSurface.slash: 1},
      ),
    ];

    final slash = sortComposerCommands(
      commands.where((command) => command.supports(ComposerMenuSurface.slash)),
      ComposerMenuSurface.slash,
    );
    final mention = sortComposerCommands(
      commands.where(
        (command) => command.supports(ComposerMenuSurface.mention),
      ),
      ComposerMenuSurface.mention,
    );
    final add = sortComposerCommands(
      commands.where((command) => command.supports(ComposerMenuSurface.add)),
      ComposerMenuSurface.add,
    );

    expect(slash.map((command) => command.kind), [
      ComposerSlashCommandKind.mcpStatus,
      ComposerSlashCommandKind.goal,
    ]);
    expect(mention.map((command) => command.kind), [
      ComposerSlashCommandKind.files,
      ComposerSlashCommandKind.goal,
    ]);
    expect(add.map((command) => command.kind), [
      ComposerSlashCommandKind.goal,
      ComposerSlashCommandKind.files,
    ]);
  });
}
