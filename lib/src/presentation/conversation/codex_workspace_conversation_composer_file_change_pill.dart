// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_diff_stats.dart';

class ComposerFileChangePill extends StatelessWidget {
  const ComposerFileChangePill({required this.changes, required this.turnDiff});

  final List<CodexFileChange> changes;
  final String? turnDiff;

  DiffStats get _stats {
    final stats = changes.fold(
      const DiffStats(0, 0),
      (total, change) => total + diffStats(change.diff),
    );
    final fallback = turnDiff;
    final hasMissingDiff = changes.any((change) => change.diff.trim().isEmpty);
    return hasMissingDiff && fallback != null && fallback.isNotEmpty
        ? diffStats(fallback)
        : stats;
  }

  bool get _statsUnknown => fileChangeStatsUnknown(changes, turnDiff);

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _stats;
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
          const SizedBox(width: 9),
          Text(
            diffCountLabel('+', stats.additions, unknown: _statsUnknown),
            style: TextStyle(color: palette.ack),
          ),
          const SizedBox(width: 8),
          Text(
            diffCountLabel('-', stats.deletions, unknown: _statsUnknown),
            style: TextStyle(color: palette.fault),
          ),
        ],
      ),
    );
  }
}
