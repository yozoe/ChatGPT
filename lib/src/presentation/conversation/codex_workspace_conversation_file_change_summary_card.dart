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
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_file_change_summary_row.dart';

class FileChangeSummaryCard extends StatelessWidget {
  const FileChangeSummaryCard({
    required this.changes,
    required this.turnDiff,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onReview,
    required this.onUndo,
    required this.canUndo,
    required this.undoRunning,
    super.key,
  });

  final List<CodexFileChange> changes;
  final String? turnDiff;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final Future<void> Function() onReview;
  final Future<void> Function() onUndo;
  final bool canUndo;
  final bool undoRunning;

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
    final visibleChanges = expanded
        ? changes
        : changes.take(3).toList(growable: false);
    final hiddenCount = changes.length - visibleChanges.length;
    return Container(
      key: const Key('file-change-summary-card'),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.field,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.edit_note_outlined,
                    size: 16,
                    color: palette.muted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        key: const Key('file-change-summary-title'),
                        '已编辑 ${changes.length} 个文件',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        key: const Key('file-change-summary-stats'),
                        TextSpan(
                          children: [
                            TextSpan(
                              text: diffCountLabel(
                                '+',
                                stats.additions,
                                unknown: _statsUnknown,
                              ),
                              style: TextStyle(color: palette.ack),
                            ),
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: diffCountLabel(
                                '-',
                                stats.deletions,
                                unknown: _statsUnknown,
                              ),
                              style: TextStyle(color: palette.fault),
                            ),
                          ],
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: canUndo || undoRunning
                      ? '撤销本次任务的文件改动'
                      : '缺少完整任务 Diff，无法安全撤销',
                  child: TextButton(
                    key: const Key('undo-file-changes-button'),
                    onPressed: canUndo ? () => unawaited(onUndo()) : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('撤销'),
                        const SizedBox(width: 4),
                        if (undoRunning)
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        else
                          const Icon(Icons.undo_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  key: const Key('review-file-changes-button'),
                  onPressed: () => unawaited(onReview()),
                  child: const Text('审核'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          for (final change in visibleChanges)
            FileChangeSummaryRow(
              change: change,
              fallbackDiff: changes.length == 1 ? turnDiff : null,
            ),
          if (hiddenCount > 0 || expanded && changes.length > 3)
            InkWell(
              onTap: () => onExpandedChanged(!expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Text(
                      expanded ? '收起文件' : '再显示 $hiddenCount 个文件',
                      style: TextStyle(color: palette.muted),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: palette.muted,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
