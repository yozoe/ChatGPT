// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_completed_turn_disclosure_state.dart';

class CompletedTurnDisclosure extends StatefulWidget {
  const CompletedTurnDisclosure({
    required this.duration,
    required this.entries,
    required this.workspacePath,
    required this.onOpenSubagent,
    super.key,
  });

  final TimelineEntry duration;
  final List<TimelineEntry> entries;
  final String? workspacePath;
  final ValueChanged<TimelineEntry> onOpenSubagent;

  @override
  State<CompletedTurnDisclosure> createState() =>
      CompletedTurnDisclosureState();
}
