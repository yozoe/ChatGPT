// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_diff_preview_line.dart';

class FileChangeHoverPreview extends StatelessWidget {
  const FileChangeHoverPreview({
    required this.path,
    required this.diff,
    required this.width,
    required this.maxHeight,
    required this.height,
  });

  final String path;
  final String diff;
  final double width;
  final double maxHeight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = diffStats(diff);
    final lines = previewLines(diff);
    final visibleLines = lines.length > 12 ? lines.take(12).toList() : lines;
    final truncated = visibleLines.length < lines.length;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('file-change-hover-preview'),
        width: width,
        height: height,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 17,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.trace,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '+${stats.additions}',
                    style: TextStyle(color: palette.ack),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-${stats.deletions}',
                    style: TextStyle(color: palette.fault),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            if (diff.trim().isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: MutedText('App Server 未提供可显示的 Diff。'),
              )
            else
              Flexible(
                child: Container(
                  color: palette.field,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText.rich(
                        TextSpan(
                          children: _previewSpans(palette, visibleLines),
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Text(
                  '仅显示前 12 行 · 打开“审核”查看完整 Diff',
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _previewSpans(
    YeknomPalette palette,
    List<DiffPreviewLine> lines,
  ) {
    return [
      for (var index = 0; index < lines.length; index++)
        TextSpan(
          text:
              '${lines[index].lineNumber?.toString().padLeft(4) ?? '    '}  '
              '${lines[index].text}\n',
          style: TextStyle(
            color: _lineColor(palette, lines[index].text),
            backgroundColor: _lineBackground(palette, lines[index].text),
          ),
        ),
    ];
  }

  Color _lineColor(YeknomPalette palette, String line) {
    return switch (line) {
      _ when line.startsWith('+++') || line.startsWith('---') => palette.muted,
      _ when line.startsWith('+') => palette.ack,
      _ when line.startsWith('-') => palette.fault,
      _ when line.startsWith('@@') => palette.active,
      _ => palette.trace,
    };
  }

  Color? _lineBackground(YeknomPalette palette, String line) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return palette.ack.withValues(alpha: 0.12);
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return palette.fault.withValues(alpha: 0.12);
    }
    return null;
  }
}
