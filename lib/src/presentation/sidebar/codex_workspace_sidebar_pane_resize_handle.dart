// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_pane_resize_handle_state.dart';

class PaneResizeHandle extends StatefulWidget {
  const PaneResizeHandle({required this.onDragDelta, super.key});

  final ValueChanged<double> onDragDelta;

  /// 创建承载悬停与拖拽状态的分隔条 State。
  /// Creates the divider state that owns hover and drag feedback.
  @override
  State<PaneResizeHandle> createState() => PaneResizeHandleState();
}
