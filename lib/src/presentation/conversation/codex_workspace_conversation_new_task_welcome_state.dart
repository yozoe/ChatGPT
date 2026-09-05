import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_new_task_suggestion_card.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_new_task_welcome.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders the new-task welcome page and the exploration follow-up menu.
class NewTaskWelcomeState extends State<NewTaskWelcome> {
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final suggestions =
        <({IconData icon, Color color, String label, String prompt})>[
          (
            icon: Icons.rocket_launch_outlined,
            color: const Color(0xFF4AA8F5),
            label: '探索并理解代码',
            prompt: '帮助我探索并理解这个项目的代码结构。',
          ),
          (
            icon: Icons.construction_outlined,
            color: const Color(0xFFA873E8),
            label: '构建新功能、应用或工具',
            prompt: '帮助我在这个项目中构建一个新功能。',
          ),
          (
            icon: Icons.sync_outlined,
            color: const Color(0xFF42C878),
            label: '审查代码并提出修改建议',
            prompt: '请审查当前代码，并提出可操作的修改建议。',
          ),
          (
            icon: Icons.bug_report_outlined,
            color: const Color(0xFFF07B35),
            label: '修复问题和失败',
            prompt: '帮助我定位并修复这个项目中的问题。',
          ),
        ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final usableWidth = (constraints.maxWidth - 48).clamp(0.0, 742.0);
        final columnCount = usableWidth >= 680
            ? 4
            : usableWidth >= 360
            ? 2
            : 1;
        final cardWidth = columnCount == 1
            ? usableWidth
            : (usableWidth - (columnCount - 1) * 12) / columnCount;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, widget.bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - widget.bottomInset - 48)
                  .clamp(0.0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 742),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.string(
                      codexNewTaskMarkSvg,
                      width: 48,
                      height: 48,
                      colorFilter: ColorFilter.mode(
                        palette.muted.withValues(alpha: 0.58),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '你想让我们在 ChatGPT 中构建什么？',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.trace,
                        fontSize: 28,
                        height: 1.18,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.45,
                      ),
                    ),
                    const SizedBox(height: 34),
                    if (widget.suggestionsVisible)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          for (
                            var index = 0;
                            index < suggestions.length;
                            index++
                          )
                            NewTaskSuggestionCard(
                              width: cardWidth,
                              icon: suggestions[index].icon,
                              iconColor: suggestions[index].color,
                              label: suggestions[index].label,
                              onPressed: () {
                                if (index == 0) {
                                  widget.onExploreSelected();
                                } else {
                                  widget.onSuggestionSelected(
                                    suggestions[index].prompt,
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
