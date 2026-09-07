// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_task_plan_panel_state.dart';

class TaskPlanPanel extends StatefulWidget {
  const TaskPlanPanel({super.key, required this.plan});

  final TaskPlan plan;

  /// 创建负责当前步骤自动聚焦的面板状态。
  /// Creates panel state that automatically focuses the current step.
  @override
  State<TaskPlanPanel> createState() => TaskPlanPanelState();
}
