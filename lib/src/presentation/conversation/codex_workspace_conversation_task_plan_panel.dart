// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_task_plan_panel_state.dart';

class TaskPlanPanel extends StatefulWidget {
  const TaskPlanPanel({required this.plan});

  final TaskPlan plan;

  /// 创建负责当前步骤自动聚焦的面板状态。
  /// Creates panel state that automatically focuses the current step.
  @override
  State<TaskPlanPanel> createState() => TaskPlanPanelState();
}
