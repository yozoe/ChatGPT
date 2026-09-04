import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_pane_resize_handle.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_side_panel_launcher.dart';

/// 承载桌面辅助面板，并在隐藏期间保留其内容状态。
/// Hosts the desktop auxiliary panel while preserving its contents when hidden.
class WorkspaceDesktopSidePanel extends StatelessWidget {
  const WorkspaceDesktopSidePanel({
    required this.expanded,
    required this.panelOpen,
    required this.hasContents,
    required this.width,
    required this.minimumContentWidth,
    required this.contents,
    required this.onResize,
    required this.onLauncherSelect,
    super.key,
  });

  final bool expanded;
  final bool panelOpen;
  final bool hasContents;
  final double width;
  final double minimumContentWidth;
  final Widget contents;
  final ValueChanged<double> onResize;
  final ValueChanged<String> onLauncherSelect;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: expanded ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!panelOpen && hasContents) return _preservedContents();
          if (constraints.maxWidth <= minimumContentWidth) {
            return hasContents ? _preservedContents() : const SizedBox.shrink();
          }
          return Row(
            children: [
              PaneResizeHandle(
                key: const Key('review-resize-handle'),
                onDragDelta: onResize,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: hasContents
                      ? contents
                      : WorkspaceSidePanelLauncher(
                          key: const ValueKey('side-panel-launcher'),
                          onSelect: onLauncherSelect,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _preservedContents() {
    return ExcludeFocus(
      child: Offstage(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: minimumContentWidth,
          maxWidth: minimumContentWidth,
          child: contents,
        ),
      ),
    );
  }
}
