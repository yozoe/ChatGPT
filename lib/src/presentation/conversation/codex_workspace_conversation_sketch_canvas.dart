import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_sketch_painter.dart';

class SketchCanvasDialog extends StatelessWidget {
  const SketchCanvasDialog({super.key});

  Future<String?> _renderSketch(List<Offset?> points, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final background = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, background);
    SketchPainter(points, strokeColor: Colors.black).paint(canvas, size);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(size.width.ceil(), size.height.ceil());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final bytes = Uint8List.view(data.buffer);
      final directory = Directory.systemTemp;
      final file = File(
        '${directory.path}/codex-sketch-${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    final points = <Offset?>[];
    const canvasSize = Size(640, 400);
    return Dialog(
      key: const Key('sketch-canvas-dialog'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '绘图',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('sketch-clear-button'),
                    tooltip: '清除画布',
                    onPressed: () => setState(points.clear),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              GestureDetector(
                key: const Key('sketch-canvas'),
                onPanStart: (details) =>
                    setState(() => points.add(details.localPosition)),
                onPanUpdate: (details) =>
                    setState(() => points.add(details.localPosition)),
                onPanEnd: (_) => setState(() => points.add(null)),
                child: Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    border: Border.all(color: palette.outline),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CustomPaint(
                    painter: SketchPainter(
                      points,
                      strokeColor: palette.onSurface,
                    ),
                    size: canvasSize,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('sketch-cancel-button'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('sketch-attach-button'),
                    onPressed: points.whereType<Offset>().isEmpty
                        ? null
                        : () async {
                            final path = await _renderSketch(
                              points,
                              canvasSize,
                            );
                            if (context.mounted && path != null) {
                              Navigator.of(context).pop(path);
                            }
                          },
                    child: const Text('添加到 Composer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
