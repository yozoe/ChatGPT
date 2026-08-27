// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_skills_library_grid.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_skill_scope_label.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_skills_library_message.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_library_section_header.dart';

class SkillsLibraryPage extends StatelessWidget {
  const SkillsLibraryPage({
    required this.controller,
    required this.search,
    required this.onChanged,
  });

  final CodexController controller;
  final TextEditingController search;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final query = search.text.trim().toLowerCase();
    final skills = controller.skills
        .where((skill) => skill.enabled)
        .where((skill) {
          return query.isEmpty ||
              skill.name.toLowerCase().contains(query) ||
              skill.label.toLowerCase().contains(query) ||
              skill.summary.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final personal = skills
        .where((skill) => skill.scope.toLowerCase() != 'system')
        .toList(growable: false);
    final system = skills
        .where((skill) => skill.scope.toLowerCase() == 'system')
        .toList(growable: false);

    return ListView(
      key: const Key('skills-page'),
      padding: const EdgeInsets.fromLTRB(72, 42, 72, 64),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1036),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '技能',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 38,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '通过任务专用技能扩展 Codex',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: palette.muted,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                key: const Key('skills-search'),
                controller: search,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  hintText: '搜索技能',
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
              const SizedBox(height: 12),
              if (controller.skillsLoading && controller.skills.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (controller.skillsError case final error?)
                SkillsLibraryMessage(
                  icon: Icons.error_outline,
                  message: error,
                  actionLabel: '重试',
                  onAction: controller.refreshSkills,
                )
              else if (skills.isEmpty)
                SkillsLibraryMessage(
                  icon: Icons.auto_awesome_outlined,
                  message: query.isEmpty
                      ? '当前项目没有可用技能。可从右上角“添加”录制一个技能。'
                      : '没有与“${search.text.trim()}”匹配的技能。',
                  actionLabel: query.isEmpty ? '刷新' : null,
                  onAction: query.isEmpty ? controller.refreshSkills : null,
                )
              else ...[
                if (personal.isNotEmpty) ...[
                  SkillScopeLabel(label: '个人与项目'),
                  const SizedBox(height: 3),
                  SkillsLibraryGrid(skills: personal),
                ],
                if (personal.isNotEmpty && system.isNotEmpty)
                  const SizedBox(height: 28),
                if (system.isNotEmpty) ...[
                  SkillScopeLabel(label: '系统技能'),
                  const SizedBox(height: 3),
                  SkillsLibraryGrid(skills: system),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
