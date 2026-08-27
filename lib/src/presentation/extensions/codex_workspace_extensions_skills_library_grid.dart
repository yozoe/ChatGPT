// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_skill_library_row.dart';

class SkillsLibraryGrid extends StatelessWidget {
  const SkillsLibraryGrid({required this.skills});
  final List<CodexSkill> skills;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns = constraints.maxWidth >= 700;
      return Wrap(
        spacing: 28,
        runSpacing: 4,
        children: skills
            .map(
              (skill) => SizedBox(
                width: twoColumns
                    ? (constraints.maxWidth - 28) / 2
                    : constraints.maxWidth,
                child: SkillLibraryRow(skill: skill),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}
