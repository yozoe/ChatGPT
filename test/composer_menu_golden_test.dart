import 'package:chatgpt/src/domain/codex_file_search_result.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_slash_command.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_slash_command_menu.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('matches the dark Composer command menu baseline', (
    tester,
  ) async {
    await _pumpMenu(
      tester,
      theme: YeknomWorkbenchTheme.dark(),
      width: 520,
      showSkills: false,
    );

    await expectLater(
      find.byKey(const Key('composer-menu-golden-boundary')),
      matchesGoldenFile('goldens/composer_command_menu_dark.png'),
    );
  });

  testWidgets('matches the light Composer mention menu baseline', (
    tester,
  ) async {
    await _pumpMenu(
      tester,
      theme: YeknomWorkbenchTheme.light(),
      width: 520,
      showSkills: true,
    );

    await expectLater(
      find.byKey(const Key('composer-menu-golden-boundary')),
      matchesGoldenFile('goldens/composer_mention_menu_light.png'),
    );
  });

  testWidgets('keeps the Composer mention menu valid at a narrow width', (
    tester,
  ) async {
    await _pumpMenu(
      tester,
      theme: YeknomWorkbenchTheme.dark(),
      width: 300,
      showSkills: true,
    );

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('composer-menu-golden-boundary')),
      matchesGoldenFile('goldens/composer_mention_menu_narrow_dark.png'),
    );
  });
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  required ThemeData theme,
  required double width,
  required bool showSkills,
}) async {
  await tester.binding.setSurfaceSize(Size(width + 40, 360));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final commands = showSkills
      ? const [
          ComposerSlashCommand(
            kind: ComposerSlashCommandKind.files,
            label: 'Files and folders',
            description: 'Attach context from this project',
            icon: Icons.attach_file,
          ),
          ComposerSlashCommand(
            kind: ComposerSlashCommandKind.workspaceContext,
            label: 'IDE context',
            description: 'IDE host is not connected',
            icon: Icons.auto_awesome_outlined,
            enabled: false,
          ),
        ]
      : const [
          ComposerSlashCommand(
            kind: ComposerSlashCommandKind.mcpStatus,
            label: 'MCP',
            description: '查看当前线程的 MCP 连接状态',
            icon: Icons.hub_outlined,
          ),
          ComposerSlashCommand(
            kind: ComposerSlashCommandKind.codeReview,
            label: 'Code review',
            description: 'Review uncommitted changes or a base branch',
            icon: Icons.fact_check_outlined,
          ),
          ComposerSlashCommand(
            kind: ComposerSlashCommandKind.archive,
            label: 'Archive chat',
            description: 'Unavailable while a task is running',
            icon: Icons.archive_outlined,
            enabled: false,
          ),
          ComposerSlashCommand(
            kind: ComposerSlashCommandKind.newChat,
            label: 'New chat',
            description: 'Start a new chat',
            icon: Icons.edit_square,
          ),
        ];
  const skills = [
    CodexSkill(
      name: 'openai-docs',
      path: '/skills/openai-docs/SKILL.md',
      description: '查询 OpenAI 官方文档',
      enabled: true,
      scope: 'system',
      displayName: 'OpenAI Docs',
      shortDescription: 'Read Codex and OpenAI docs',
    ),
    CodexSkill(
      name: 'long-skill',
      path: '/skills/long-skill/SKILL.md',
      description: '验证长名称布局',
      enabled: true,
      scope: 'user',
      displayName: 'A deliberately long skill name for truncation',
      shortDescription: 'Verify truncation for long skill names',
    ),
  ];

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: ColoredBox(
        color: YeknomPalette.fromBrightness(theme.brightness).bench,
        child: Center(
          child: RepaintBoundary(
            key: const Key('composer-menu-golden-boundary'),
            child: SizedBox(
              width: width,
              child: ComposerSlashCommandMenu(
                commands: commands,
                skills: showSkills ? skills : const [],
                files: showSkills
                    ? const [
                        CodexFileSearchResult(
                          fileName: 'composer_panel.dart',
                          path: '/workspace/lib/composer_panel.dart',
                          root: '/workspace',
                          matchType: 'file',
                          score: 100,
                          indices: const [0, 1, 2],
                        ),
                      ]
                    : const [],
                showSkills: showSkills,
                skillsLoading: false,
                skillsError: null,
                filesLoading: false,
                filesError: null,
                searchQuery: showSkills ? 'com' : '',
                commandScrollKeys: const {},
                skillScrollKeys: const {},
                fileScrollKeys: const {},
                selectedIndex: 0,
                onSelected: (_) {},
                onSkillSelected: (_) {},
                onFileSelected: (_) {},
                onItemHovered: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
