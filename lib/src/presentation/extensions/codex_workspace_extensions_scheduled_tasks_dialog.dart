// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_tasks_dialog_state.dart';

class ScheduledTasksDialog extends StatefulWidget {
  const ScheduledTasksDialog({required this.controller, this.initialPrompt});

  final CodexController controller;
  final String? initialPrompt;

  @override
  State<ScheduledTasksDialog> createState() => ScheduledTasksDialogState();
}
