import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_elapsed_turn_group_state.dart';

/// A compact, reversible summary for consecutive turns that only report time.
class ElapsedTurnGroup extends StatefulWidget {
  const ElapsedTurnGroup({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  State<ElapsedTurnGroup> createState() => ElapsedTurnGroupState();
}
