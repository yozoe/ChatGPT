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
}
