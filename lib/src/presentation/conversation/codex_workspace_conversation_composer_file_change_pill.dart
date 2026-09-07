// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class ComposerFileChangePill extends StatelessWidget {
  const ComposerFileChangePill({
    super.key,
    required this.changes,
    required this.turnDiff,
  });

  final List<CodexFileChange> changes;
  final String? turnDiff;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = reliableFileChangeStats(changes, turnDiff);
    return Container(
      key: const Key('composer-file-change-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${changes.length} 个文件已更改',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
          if (stats != null) ...[
            const SizedBox(width: 9),
            Text('+${stats.additions}', style: TextStyle(color: palette.ack)),
            const SizedBox(width: 8),
            Text('-${stats.deletions}', style: TextStyle(color: palette.fault)),
          ],
        ],
      ),
    );
  }
}
