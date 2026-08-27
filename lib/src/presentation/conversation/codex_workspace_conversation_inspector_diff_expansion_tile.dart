// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class InspectorDiffExpansionTile extends StatelessWidget {
  const InspectorDiffExpansionTile({
    required this.title,
    required this.subtitle,
    required this.diff,
  });

  final String title;
  final String subtitle;
  final String diff;

  /// 构建与 Codex 环境信息列表一致的紧凑可展开 Diff 项。
  /// Builds a compact expandable Diff row consistent with Codex environment lists.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        expansionTileTheme: ExpansionTileThemeData(
          iconColor: palette.trace,
          collapsedIconColor: palette.trace,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 10),
        ),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        leading: Icon(
          Icons.description_outlined,
          size: 19,
          color: palette.trace,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.muted, fontSize: 12),
        ),
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 33),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
            ),
            child: diff.isEmpty
                ? const MutedText('App Server 未提供可显示的 Diff。')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText.rich(
                      TextSpan(children: _diffSpans(palette, diff)),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 按 unified Diff 行类型与当前主题语义色为文本片段分配颜色。
  /// Assigns colors to text spans using unified-diff line types and theme semantics.
  List<TextSpan> _diffSpans(YeknomPalette palette, String value) {
    return value
        .split('\n')
        .map((line) {
          final color = switch (line) {
            _ when line.startsWith('+++') || line.startsWith('---') =>
              palette.muted,
            _ when line.startsWith('+') => palette.ack,
            _ when line.startsWith('-') => palette.fault,
            _ when line.startsWith('@@') => palette.active,
            _ => palette.trace,
          };
          return TextSpan(
            text: '$line\n',
            style: TextStyle(color: color),
          );
        })
        .toList(growable: false);
  }
}
