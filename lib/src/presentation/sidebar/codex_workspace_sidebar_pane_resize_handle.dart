// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_pane_resize_handle_state.dart';

class PaneResizeHandle extends StatefulWidget {
  const PaneResizeHandle({required this.onDragDelta, super.key});

  final ValueChanged<double> onDragDelta;

  /// 创建承载悬停与拖拽状态的分隔条 State。
  /// Creates the divider state that owns hover and drag feedback.
  @override
  State<PaneResizeHandle> createState() => PaneResizeHandleState();
}
