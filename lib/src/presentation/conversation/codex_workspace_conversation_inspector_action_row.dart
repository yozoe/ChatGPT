// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class InspectorActionRow extends StatelessWidget {
  const InspectorActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final Widget? trailing;

  /// 构建可打开相应 Git 工作流的 Codex 环境信息行。
  /// Builds a Codex environment row that opens its corresponding Git workflow.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return InkWell(
      onTap: () => unawaited(onTap()),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: palette.trace),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
