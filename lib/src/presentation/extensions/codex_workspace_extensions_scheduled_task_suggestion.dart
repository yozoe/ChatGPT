// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';

class ScheduledTaskSuggestion {
  const ScheduledTaskSuggestion({
    required this.icon,
    required this.color,
    required this.title,
    required this.schedule,
    required this.prompt,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String schedule;
  final String prompt;
}
