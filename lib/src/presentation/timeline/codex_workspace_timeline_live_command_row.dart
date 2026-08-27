// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_activity_shimmer.dart';

class LiveCommandRow extends StatelessWidget {
  const LiveCommandRow({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      key: const Key('live-command-row'),
      liveRegion: true,
      label: '正在运行命令：$command',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 3, 6, 3),
        child: Row(
          children: [
            Icon(Icons.terminal_outlined, size: 16, color: palette.muted),
            const SizedBox(width: 9),
            Expanded(
              child: SelectionArea(
                child: LiveActivityShimmer(
                  shimmerKey: const Key('live-command-shimmer'),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '正在运行 ',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.muted),
                        ),
                        TextSpan(
                          text: command,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.trace,
                                fontFamily: 'monospace',
                              ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
