import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ComposerPastedTextCard extends StatelessWidget {
  const ComposerPastedTextCard({
    required this.id,
    required this.label,
    required this.onShowInComposer,
    required this.onRemove,
    super.key,
  });

  final int id;
  final String label;
  final VoidCallback onShowInComposer;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.fromLTRB(6, 5, 4, 5),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.select_all_rounded,
              size: 19,
              color: palette.muted,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.trace,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Semantics(
                  button: true,
                  label: '在文本框中显示完整的粘贴文本',
                  child: InkWell(
                    key: ValueKey('composer-pasted-text-show-$id'),
                    onTap: onShowInComposer,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        '在文本框中显示 ›',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: ValueKey('composer-pasted-text-remove-$id'),
            tooltip: '移除粘贴文本',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 15),
            color: palette.muted,
            padding: const EdgeInsets.all(3),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
