// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_inspector_diff_expansion_tile.dart';

/// 在检查器中展示本轮完整 Diff 及各文件变更的可展开列表。
/// Displays the turn-wide diff and per-file changes as expandable inspector rows.
class InspectorFileChangesList extends StatelessWidget {
  const InspectorFileChangesList({
    required this.changes,
    required this.turnDiff,
  });

  final List<CodexFileChange> changes;
  final String? turnDiff;

  /// 以信息卡中的紧凑行展示完整任务和单文件 Diff。
  /// Shows task and file diffs as compact rows inside the information card.
  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty && (turnDiff == null || turnDiff!.isEmpty)) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(left: 38, top: 4),
          child: MutedText('任务执行后，AI 修改的文件会显示在这里。'),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (turnDiff case final diff?)
          InspectorDiffExpansionTile(
            title: '本次任务完整 Diff',
            subtitle: '来自 Codex App Server',
            diff: diff,
          ),
        ...changes.map(
          (change) => InspectorDiffExpansionTile(
            title: change.path,
            subtitle: change.kind,
            diff: change.diff,
          ),
        ),
      ],
    );
  }
}
