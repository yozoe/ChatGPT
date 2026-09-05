import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

/// Floating exploration menu positioned independently above the Composer.
class NewTaskExploreMenu extends StatelessWidget {
  const NewTaskExploreMenu({required this.onSelected, super.key});

  static const prompts = [
    '探索并了解功能的工作原理',
    '探索某项功能的实现方案',
    '探索并比较架构方案',
    '探索并编写 API 文档',
  ];

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return SingleChildScrollView(
      key: const Key('new-task-explore-menu'),
      child: Column(
        children: [
          for (final prompt in prompts)
            Semantics(
              button: true,
              label: prompt,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('new-task-explore-$prompt'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(prompt),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.rocket_launch_outlined,
                          size: 15,
                          color: palette.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            prompt,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
