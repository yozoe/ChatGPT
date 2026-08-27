// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
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
