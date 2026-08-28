// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_sidebar_workspace_tile.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
        button: true,
        label: '${widget.expanded ? '收起' : '展开'}项目任务 $_displayName',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hovering ? palette.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: widget.onToggleExpanded,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              child: Row(
                children: [
                  Tooltip(
                    message: widget.expanded ? '收起项目任务' : '展开项目任务',
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(widget.expanded),
                        child: buildCodexSidebarFolderIcon(
                          key: ValueKey(
                            'sidebar-workspace-folder-${widget.workspace.primaryPath}',
                          ),
                          expanded: widget.expanded,
                          color: widget.active ? palette.active : palette.muted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
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

/// Builds the distinct open and closed folder outlines used by Codex project nodes.
Widget buildCodexSidebarFolderIcon({
  required Key key,
  required bool expanded,
  required Color color,
}) {
  return SizedBox(
    key: key,
    width: 16,
    height: 16,
    child: SvgPicture.string(
      expanded ? _codexOpenFolderSvg : _codexClosedFolderSvg,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

const _codexOpenFolderSvg = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M3.5 8.25H9.2L11.15 10.5H20.1C21.25 10.5 22.08 11.6 21.8 12.72L20.6 17.55C20.38 18.43 19.59 19 18.68 19H5.8C4.83 19 4.02 18.3 3.87 17.35L3.08 12.28C2.89 11.05 3.84 10 5.08 10H7.2L6.4 8.9C5.95 8.3 5.25 8 4.5 8H3.5V8.25Z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
  <path d="M3.5 8.25V6.75C3.5 5.78 4.28 5 5.25 5H9.15L11.1 7.25H18.75C19.72 7.25 20.5 8.03 20.5 9V10.5" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
</svg>
''';

const _codexClosedFolderSvg = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M3.5 6.75C3.5 5.78 4.28 5 5.25 5H9.15L11.1 7.25H18.75C19.72 7.25 20.5 8.03 20.5 9V17.25C20.5 18.22 19.72 19 18.75 19H5.25C4.28 19 3.5 18.22 3.5 17.25V6.75Z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
  <path d="M3.5 9H20.5" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
</svg>
''';
