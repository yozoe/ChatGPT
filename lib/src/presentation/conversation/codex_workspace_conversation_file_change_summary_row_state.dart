// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_file_change_summary_row.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_file_change_hover_preview.dart';

class FileChangeSummaryRowState extends State<FileChangeSummaryRow> {
  static const _previewMargin = 12.0;
  static const _previewGap = 8.0;
  static const _previewMaxWidth = 560.0;
  static const _previewMaxHeight = 330.0;

  final LayerLink _layerLink = LayerLink();
  final ValueNotifier<int> _previewVersion = ValueNotifier(0);
  OverlayEntry? _previewEntry;
  Timer? _showTimer;
  Timer? _hideTimer;
  bool _hovering = false;
  Offset _previewOffset = Offset.zero;
  Alignment _targetAnchor = Alignment.topLeft;
  Alignment _followerAnchor = Alignment.bottomLeft;
  double _previewWidth = _previewMaxWidth;
  double _previewMaxHeightValue = _previewMaxHeight;
  double _previewHeight = _previewMaxHeight;
  bool _previewRefreshScheduled = false;

  String get _diff => widget.change.diff.trim().isEmpty
      ? (widget.fallbackDiff ?? '')
      : widget.change.diff;

  bool _updatePreviewGeometry() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return false;
    final viewport = MediaQuery.sizeOf(context);
    final targetTopLeft = renderObject.localToGlobal(Offset.zero);
    final targetBottom = targetTopLeft.dy + renderObject.size.height;
    final availableAbove = targetTopLeft.dy - _previewMargin - _previewGap;
    final availableBelow =
        viewport.height - targetBottom - _previewMargin - _previewGap;
    final showAbove = availableAbove >= availableBelow;
    final availableHeight = showAbove ? availableAbove : availableBelow;
    final width = (viewport.width - _previewMargin * 2)
        .clamp(1.0, _previewMaxWidth)
        .toDouble();
    final horizontalShift =
        targetTopLeft.dx + width > viewport.width - _previewMargin
        ? viewport.width - _previewMargin - targetTopLeft.dx - width
        : targetTopLeft.dx < _previewMargin
        ? _previewMargin - targetTopLeft.dx
        : 0.0;
    _previewWidth = width;
    _previewMaxHeightValue = availableHeight
        .clamp(1.0, _previewMaxHeight)
        .toDouble();
    final previewLineCount = previewLines(_diff).length;
    final isSvg = widget.change.path.toLowerCase().endsWith('.svg');
    final estimatedHeight = isSvg
        ? 250.0
        : _diff.trim().isEmpty
        ? 96.0
        : 60.0 +
              (previewLineCount > 12 ? 12 : previewLineCount) * 18.0 +
              (previewLineCount > 12 ? 24.0 : 0.0);
    _previewHeight = estimatedHeight < _previewMaxHeightValue
        ? estimatedHeight
        : _previewMaxHeightValue;
    _previewOffset = Offset(
      horizontalShift,
      showAbove
          ? -_previewHeight - _previewGap
          : renderObject.size.height + _previewGap,
    );
    _targetAnchor = Alignment.topLeft;
    _followerAnchor = Alignment.topLeft;
    return true;
  }

  void _showPreview() {
    _hideTimer?.cancel();
    if (_previewEntry != null || !mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || !_updatePreviewGeometry()) return;

    final entry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<int>(
        valueListenable: _previewVersion,
        builder: (context, _, _) => CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: _targetAnchor,
          followerAnchor: _followerAnchor,
          offset: _previewOffset,
          child: IgnorePointer(
            child: UnconstrainedBox(
              alignment: Alignment.topLeft,
              child: FileChangeHoverPreview(
                path: widget.change.path,
                diff: _diff,
                width: _previewWidth,
                maxHeight: _previewMaxHeightValue,
                height: _previewHeight,
              ),
            ),
          ),
        ),
      ),
    );
    _previewEntry = entry;
    overlay.insert(entry);
  }

  void _schedulePreviewShow() {
    _hideTimer?.cancel();
    _showTimer?.cancel();
    _showTimer = Timer(codexHoverPopupDelay, () {
      _showTimer = null;
      if (mounted && _hovering) _showPreview();
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _showTimer = null;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      _previewEntry?.remove();
      _previewEntry = null;
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _previewEntry?.remove();
    _previewVersion.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FileChangeSummaryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.change.path != widget.change.path ||
        oldWidget.change.diff != widget.change.diff ||
        oldWidget.fallbackDiff != widget.fallbackDiff) {
      if (_previewEntry != null && !_previewRefreshScheduled) {
        _previewRefreshScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _previewRefreshScheduled = false;
          if (mounted && _previewEntry != null) {
            _updatePreviewGeometry();
            _previewVersion.value++;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = diffStats(_diff);
    final unknown = _diff.trim().isEmpty;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        key: ValueKey('file-change-row-${widget.change.path}'),
        onEnter: (_) {
          setState(() => _hovering = true);
          _schedulePreviewShow();
        },
        onExit: (_) {
          setState(() => _hovering = false);
          _scheduleHide();
        },
        cursor: SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: palette.field.withValues(alpha: _hovering ? 0.68 : 0.42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.change.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.trace),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                diffCountLabel('+', stats.additions, unknown: unknown),
                style: TextStyle(color: palette.ack),
              ),
              const SizedBox(width: 10),
              Text(
                diffCountLabel('-', stats.deletions, unknown: unknown),
                style: TextStyle(color: palette.fault),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
