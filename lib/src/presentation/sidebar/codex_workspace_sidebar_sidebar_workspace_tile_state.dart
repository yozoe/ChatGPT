// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_workspace_tile.dart';

class SidebarWorkspaceTileState extends State<SidebarWorkspaceTile> {
  bool _hovering = false;

  /// 从主目录路径提取适合侧栏识别的工作区名称。
  /// Extracts a recognizable sidebar name from the primary-directory path.
  String get _displayName =>
      widget.workspace.name ??
      workspaceDirectoryName(widget.workspace.primaryPath);

  /// 构建项目节点；完整路径收纳在项目详情卡片中，不占用任务列表空间。
  /// Builds the project node; the details card keeps the full path out of the task list.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovering = true);
        widget.onHoverStart(context);
      },
      onExit: (_) {
        setState(() => _hovering = false);
        widget.onHoverEnd();
      },
      child: Semantics(
        selected: widget.active,
        button: !widget.active,
        label: widget.active ? '当前工作区 $_displayName' : '切换到工作区 $_displayName',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hovering ? palette.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: widget.active || !widget.enabled ? null : widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    widget.active
                        ? Icons.folder_special_outlined
                        : Icons.folder_outlined,
                    size: 16,
                    color: widget.active ? palette.active : palette.muted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.active ? palette.trace : palette.muted,
                        fontSize: 12,
                        fontWeight: widget.active
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'sidebar-workspace-toggle-${widget.workspace.primaryPath}',
                    ),
                    tooltip: widget.expanded ? '收起项目任务' : '展开项目任务',
                    onPressed: widget.onToggleExpanded,
                    icon: Icon(
                      widget.expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 16,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (widget.pinned)
                    Icon(Icons.push_pin, size: 13, color: palette.faint),
                  if (_hovering) ...[
                    IconButton(
                      key: ValueKey(
                        'sidebar-workspace-more-${widget.workspace.primaryPath}',
                      ),
                      tooltip: '项目菜单',
                      onPressed: () => widget.onMore(context),
                      icon: const Icon(Icons.more_horiz, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      key: ValueKey(
                        'sidebar-workspace-edit-${widget.workspace.primaryPath}',
                      ),
                      tooltip: '新建任务',
                      onPressed: widget.canCreateTask
                          ? () => widget.onEdit(context)
                          : null,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ] else if (widget.workspace.additionalPaths.isNotEmpty)
                    Text(
                      '+${widget.workspace.additionalPaths.length}',
                      style: TextStyle(color: palette.faint, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
