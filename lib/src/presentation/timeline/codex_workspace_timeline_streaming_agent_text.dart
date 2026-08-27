// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class StreamingAgentText extends StatelessWidget {
  const StreamingAgentText(this.data);

  final String data;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    return SelectionArea(
      key: const Key('agent-streaming-selection'),
      child: Text(
        stableStreamingAgentText(data),
        key: const Key('agent-streaming-text'),
        style: style,
        strutStyle: style == null
            ? null
            : StrutStyle.fromTextStyle(style, forceStrutHeight: true),
      ),
    );
  }
}
