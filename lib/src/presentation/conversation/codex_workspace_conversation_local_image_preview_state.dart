// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_local_image_preview.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_image_preview_action.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_image_preview_zoom_button.dart';

class LocalImagePreviewState extends State<LocalImagePreview> {
  static const _minimumActualScale = 0.1;
  static const _maximumActualScale = 5.0;
  static const _zoomFactor = 1.25;
  static const controlSurface = Color(0xFF252525);
  static const controlRaised = Color(0xFF383838);
  static const controlInk = Color(0xFFE7E7E7);
  static const controlMuted = Color(0xFFA8A8A8);

  final TransformationController _transformationController =
      TransformationController();
  late final ImageStreamListener _imageStreamListener;
  ImageStream? _imageStream;
  Size? _imagePixelSize;
  Size _viewportSize = Size.zero;
  double _minimumTransformScale = 0.1;
  double _maximumTransformScale = 5;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _imageStreamListener = ImageStreamListener(
      _handleImageFrame,
      // The visible Image widget owns the broken-image fallback. This second
      // listener only observes intrinsic dimensions and must not surface the
      // same file failure as an uncaught framework error.
      onError: (error, stackTrace) {},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant LocalImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _resolveImageSize();
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageStreamListener);
    _transformationController.dispose();
    super.dispose();
  }

  void _resolveImageSize() {
    final stream = FileImage(
      File(widget.path),
    ).resolve(createLocalImageConfiguration(context));
    if (_imageStream?.key == stream.key) return;
    _imageStream?.removeListener(_imageStreamListener);
    _imageStream = stream..addListener(_imageStreamListener);
  }

  void _handleImageFrame(ImageInfo info, bool synchronousCall) {
    final next = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    if (_imagePixelSize == next) return;
    if (synchronousCall) {
      _imagePixelSize = next;
    } else if (mounted) {
      setState(() => _imagePixelSize = next);
    }
  }

  void _close() => Navigator.of(context).pop();

  void _setScale(double value) {
    final next = value
        .clamp(_minimumTransformScale, _maximumTransformScale)
        .toDouble();
    if (_viewportSize.isEmpty) {
      _transformationController.value = Matrix4.diagonal3Values(next, next, 1);
    } else {
      final viewportCenter = _viewportSize.center(Offset.zero);
      final sceneCenter = _transformationController.toScene(viewportCenter);
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(viewportCenter.dx, viewportCenter.dy, 0, 1)
        ..scaleByDouble(next, next, 1, 1)
        ..translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0, 1);
    }
    setState(() => _scale = next);
  }

  void _zoomIn() => _setScale(_scale * _zoomFactor);

  void _zoomOut() => _setScale(_scale / _zoomFactor);

  void _resetScale() {
    _transformationController.value = Matrix4.identity();
    setState(() => _scale = 1);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add) {
      _zoomIn();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      _resetScale();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: '图片预览',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: SafeArea(
              minimum: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewportSize = Size(
                    math.max(0, constraints.maxWidth - 16),
                    math.max(0, constraints.maxHeight - 124),
                  );
                  final pixelSize = _imagePixelSize;
                  final baseScale =
                      pixelSize == null ||
                          pixelSize.isEmpty ||
                          _viewportSize.isEmpty
                      ? 1.0
                      : math.min(
                          1.0,
                          math.min(
                            _viewportSize.width / pixelSize.width,
                            _viewportSize.height / pixelSize.height,
                          ),
                        );
                  _minimumTransformScale = math.min(
                    1.0,
                    _minimumActualScale / baseScale,
                  );
                  _maximumTransformScale = math.max(
                    1.0,
                    _maximumActualScale / baseScale,
                  );
                  final zoomPercent = '${(baseScale * _scale * 100).round()}%';
                  return Stack(
                    children: [
                      Positioned.fill(
                        top: 58,
                        bottom: 66,
                        left: 8,
                        right: 8,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          onDoubleTap: _scale == 1
                              ? () => _setScale(2)
                              : _resetScale,
                          child: InteractiveViewer(
                            key: const Key('composer-image-interactive-viewer'),
                            transformationController: _transformationController,
                            alignment: Alignment.topLeft,
                            minScale: _minimumTransformScale,
                            maxScale: _maximumTransformScale,
                            onInteractionUpdate: (_) {
                              final next = _transformationController.value
                                  .getMaxScaleOnAxis()
                                  .clamp(
                                    _minimumTransformScale,
                                    _maximumTransformScale,
                                  )
                                  .toDouble();
                              if ((next - _scale).abs() < 0.001) return;
                              setState(() => _scale = next);
                            },
                            child: SizedBox.expand(
                              child: Image.file(
                                File(widget.path),
                                key: const Key('composer-image-preview'),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white54,
                                        size: 56,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ImagePreviewAction(
                              key: const Key('composer-image-open-button'),
                              tooltip: '在默认应用中打开',
                              icon: Icons.edit_outlined,
                              onPressed: widget.onOpenExternally,
                            ),
                            const SizedBox(width: 8),
                            ImagePreviewAction(
                              key: const Key('composer-image-save-button'),
                              tooltip: '保存图片副本',
                              icon: Icons.file_download_outlined,
                              onPressed: widget.onSaveCopy,
                            ),
                            const SizedBox(width: 8),
                            ImagePreviewAction(
                              key: const Key('composer-image-close-button'),
                              tooltip: '关闭预览',
                              icon: Icons.close,
                              onPressed: _close,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: controlSurface,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: Colors.white12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 18,
                                  offset: Offset(0, 7),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ImagePreviewZoomButton(
                                    key: const Key('composer-image-zoom-out'),
                                    tooltip: '缩小',
                                    icon: Icons.remove,
                                    onPressed:
                                        _scale <= _minimumTransformScale + 0.001
                                        ? null
                                        : _zoomOut,
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      zoomPercent,
                                      key: const Key(
                                        'composer-image-zoom-label',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: controlInk,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ImagePreviewZoomButton(
                                    key: const Key('composer-image-zoom-in'),
                                    tooltip: '放大',
                                    icon: Icons.add,
                                    onPressed:
                                        _scale >= _maximumTransformScale - 0.001
                                        ? null
                                        : _zoomIn,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
