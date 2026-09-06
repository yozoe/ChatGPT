import 'dart:async';

import 'package:chatgpt/src/presentation/files/workspace_code_syntax_highlighter.dart';
import 'package:chatgpt/src/presentation/files/workspace_file_preview_reader.dart';
import 'package:chatgpt/src/presentation/files/workspace_source_file_preview.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Owns bounded file loading and syntax highlighting for one workspace tab.
class WorkspaceSourceFilePreviewState
    extends State<WorkspaceSourceFilePreview> {
  static const int _maximumPreviewBytes = 1024 * 1024;

  String? _content;
  String? _error;
  bool _loading = true;
  int _loadGeneration = 0;
  TextSpan? _highlightedContent;
  bool? _highlightedDark;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant WorkspaceSourceFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.workspacePath != widget.workspacePath) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _content = null;
      _error = null;
      _highlightedContent = null;
      _highlightedDark = null;
    });
    final preview = await WorkspaceFilePreviewReader(
      workspacePath: widget.workspacePath,
      maximumBytes: _maximumPreviewBytes,
    ).read(widget.reference.path);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loading = false;
      _content = preview.content;
      _error = preview.error;
    });
  }

  TextSpan _highlight(bool dark) {
    if (_highlightedContent != null && _highlightedDark == dark) {
      return _highlightedContent!;
    }
    _highlightedDark = dark;
    return _highlightedContent = WorkspaceCodeSyntaxHighlighter(
      dark: dark,
    ).highlight(content: _content ?? '', path: widget.reference.path);
  }

  String get _fileName {
    final segments = widget.reference.uri.pathSegments;
    return segments.isEmpty ? widget.reference.path : segments.last;
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return ColoredBox(
      key: ValueKey('source-workspace-page-${widget.reference.path}'),
      color: palette.module,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: palette.muted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.reference.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: palette.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('source-workspace-close-button'),
                  tooltip: '关闭文件',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(palette)),
        ],
      ),
    );
  }

  Widget _buildBody(YeknomPalette palette) {
    if (_loading) {
      return Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 1.7,
            color: palette.active,
          ),
        ),
      );
    }
    if (_error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 34, color: palette.muted),
              const SizedBox(height: 12),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => unawaited(_load()),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新载入'),
              ),
            ],
          ),
        ),
      );
    }
    final content = _content ?? '';
    final lineCount = '\n'.allMatches(content).length + 1;
    final lineNumbers = List<String>.generate(
      lineCount,
      (index) => '${index + 1}',
    ).join('\n');
    return SingleChildScrollView(
      key: const Key('source-workspace-vertical-scroll'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: SingleChildScrollView(
        key: const Key('source-workspace-horizontal-scroll'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lineNumbers,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.faint,
                fontSize: 12,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 14),
            SelectableText.rich(
              _highlight(palette.dark),
              key: const Key('source-workspace-content'),
              style: TextStyle(
                color: palette.trace,
                fontSize: 12,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
