// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_history_thread_tile_state.dart';

class HistoryThreadTile extends StatefulWidget {
  const HistoryThreadTile({
    required this.thread,
    required this.selected,
    required this.pinned,
    required this.statusIndicator,
    required this.running,
    required this.processing,
    required this.enabled,
    required this.actionsEnabled,
    required this.selectionMode,
    required this.batchSelected,
    required this.onTap,
    this.onRename,
    this.onArchive,
    this.onDelete,
    this.onTogglePin,
  });

  final CodexThread thread;
  final bool selected;
  final bool pinned;
  final ThreadStatusIndicator? statusIndicator;
  final bool running;
  final bool processing;
  final bool enabled;
  final bool actionsEnabled;
  final bool selectionMode;
  final bool batchSelected;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePin;

  /// 构建带有悬停快捷操作和右键菜单的历史线程项。
  /// Builds a history-thread item with hover shortcuts and a context menu.
  @override
  State<HistoryThreadTile> createState() => HistoryThreadTileState();
}
