// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_history_thread_tile.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_thread_status_mark.dart';

class HistoryThreadTileState extends State<HistoryThreadTile> {
  bool _hovering = false;

  /// 显示任务行的完整右键操作菜单。
  /// Shows the task row's full context-action menu.
  Future<void> _showContextMenu(TapUpDetails details) async {
    if (!widget.actionsEnabled || !widget.enabled || widget.selectionMode) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final position = details.globalPosition;
    final action = await showMenu<ThreadAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        PopupMenuItem(
          value: ThreadAction.pin,
          child: Text(widget.pinned ? '取消置顶' : '置顶'),
        ),
        const PopupMenuItem(value: ThreadAction.rename, child: Text('重命名')),
        PopupMenuItem(
          value: ThreadAction.archive,
          enabled: widget.onArchive != null,
          child: Text(widget.running ? '归档（请先停止任务）' : '归档'),
        ),
        const PopupMenuItem(value: ThreadAction.delete, child: Text('永久删除')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case ThreadAction.rename:
        widget.onRename?.call();
      case ThreadAction.archive:
        widget.onArchive?.call();
      case ThreadAction.delete:
        widget.onDelete?.call();
      case ThreadAction.pin:
        widget.onTogglePin?.call();
    }
  }

  /// 构建与 Codex 侧栏一致的紧凑悬停操作图标。
  /// Builds compact hover action icons consistent with the Codex sidebar.
  Widget _buildHoverAction({
    required String keySuffix,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        key: ValueKey('sidebar-thread-$keySuffix-${widget.thread.id}'),
        onPressed: widget.enabled ? onPressed : null,
        icon: Icon(icon, size: 16),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        splashRadius: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final showHoverActions =
        _hovering &&
        widget.actionsEnabled &&
        !widget.selectionMode &&
        !widget.running &&
        !widget.processing;
    return Material(
      key: ValueKey('sidebar-thread-tile-${widget.thread.id}'),
      color: widget.selected ? palette.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onSecondaryTapUp: _showContextMenu,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              // The left inset preserves the project-tree hierarchy; the compact
              // vertical inset keeps a selected task from reading as a large card.
              padding: const EdgeInsets.fromLTRB(30, 4, 8, 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Row(
                  children: [
                    if (widget.selectionMode)
                      Checkbox(
                        value: widget.batchSelected,
                        onChanged: widget.enabled
                            ? (_) => widget.onTap()
                            : null,
                      ),
                    Expanded(
                      child: Column(
                        // Keep the fade aligned with the task bubble's trailing
                        // edge instead of the rendered title's intrinsic width.
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ShaderMask(
                            key: ValueKey(
                              'sidebar-thread-title-fade-${widget.thread.id}',
                            ),
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (bounds) => const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                              ],
                              stops: [0, 0.78, 1],
                            ).createShader(bounds),
                            child: Text(
                              widget.thread.title,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                color: widget.selected
                                    ? palette.trace
                                    : palette.muted,
                                fontSize: 13,
                                fontWeight: widget.selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.processing)
                      Tooltip(
                        message: '任务处理中',
                        child: SizedBox(
                          key: const Key('sidebar-updating-task-indicator'),
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.25,
                            color: palette.active,
                          ),
                        ),
                      )
                    else if (widget.running)
                      Tooltip(
                        message: '任务进行中；停止后才能归档',
                        child: SizedBox(
                          key: const Key('sidebar-running-task-indicator'),
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.25,
                            color: palette.active,
                          ),
                        ),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.statusIndicator case final indicator?)
                            if (!(_hovering &&
                                indicator == ThreadStatusIndicator.completed))
                              ThreadStatusMark(indicator: indicator),
                          if (showHoverActions) ...[
                            _buildHoverAction(
                              keySuffix: 'pin',
                              tooltip: widget.pinned ? '取消置顶任务' : '置顶任务',
                              icon: widget.pinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              onPressed: widget.onTogglePin,
                            ),
                            _buildHoverAction(
                              keySuffix: 'archive',
                              tooltip: '归档任务',
                              icon: Icons.archive_outlined,
                              onPressed: widget.onArchive,
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
