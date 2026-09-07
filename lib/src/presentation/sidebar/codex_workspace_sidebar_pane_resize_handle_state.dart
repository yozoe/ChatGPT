// Extracted class from codex_workspace_sidebar.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_pane_resize_handle.dart';

class PaneResizeHandleState extends State<PaneResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;
  bool _focused = false;

  /// 构建桌面窗格的可拖拽分隔条，并在悬停或拖动时提高可见性。
  /// Builds a desktop pane divider that becomes more visible on hover or drag.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final active = _hovered || _dragging || _focused;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              widget.onDragDelta(-12),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              widget.onDragDelta(12),
        },
        child: Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          child: Semantics(
            label: '调整窗格宽度',
            focusable: true,
            onDecrease: () => widget.onDragDelta(-12),
            onIncrease: () => widget.onDragDelta(12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragUpdate: (details) =>
                  widget.onDragDelta(details.delta.dx),
              onHorizontalDragEnd: (_) => setState(() => _dragging = false),
              onHorizontalDragCancel: () => setState(() => _dragging = false),
              child: SizedBox(
                width: 8,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: active ? 2 : 1,
                    color: active ? palette.active : palette.border,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
