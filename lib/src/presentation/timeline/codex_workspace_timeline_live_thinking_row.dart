// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_thinking_row_state.dart';

class LiveThinkingRow extends StatefulWidget {
  const LiveThinkingRow({super.key, this.label = '正在思考'});

  final String label;

  @override
  State<LiveThinkingRow> createState() => LiveThinkingRowState();
}
