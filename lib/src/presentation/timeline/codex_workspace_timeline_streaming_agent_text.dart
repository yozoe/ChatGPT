// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class StreamingAgentText extends StatelessWidget {
  const StreamingAgentText(this.data, {super.key});

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
