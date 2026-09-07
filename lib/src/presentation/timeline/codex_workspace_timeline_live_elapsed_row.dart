// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_elapsed_row_state.dart';

class LiveElapsedRow extends StatefulWidget {
  const LiveElapsedRow({super.key, required this.startedAt});

  final DateTime startedAt;

  @override
  State<LiveElapsedRow> createState() => LiveElapsedRowState();
}
