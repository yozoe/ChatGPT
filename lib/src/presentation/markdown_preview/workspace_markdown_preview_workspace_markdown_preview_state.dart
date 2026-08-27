// Extracted class from workspace_markdown_preview.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_support.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_workspace_markdown_preview.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_markdown_mode_switch.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_location_label.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_workspace_markdown_image.dart';

class WorkspaceMarkdownPreviewState extends State<WorkspaceMarkdownPreview> {
  final ScrollController _previewController = ScrollController();
  final ScrollController _sourceController = ScrollController();
  final ScrollController _sourceHorizontalController = ScrollController();
  final List<WorkspaceFileReference> _history = [];

  late WorkspaceFileReference _reference;
  MarkdownViewMode _mode = MarkdownViewMode.preview;
  String? _content;
  List<String> _sourceLines = const [];
  Object? _loadError;
  bool _loading = true;
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _reference = widget.reference;
    unawaited(_load(_reference));
  }

  @override
  void dispose() {
    _loadRevision += 1;
    _previewController.dispose();
    _sourceController.dispose();
    _sourceHorizontalController.dispose();
    super.dispose();
  }

  Future<void> _load(WorkspaceFileReference reference) async {
    final revision = ++_loadRevision;
    setState(() {
      _reference = reference;
      _loading = true;
      _loadError = null;
      _content = null;
      _sourceLines = const [];
    });
    try {
      final validatedReference = await _validatedReference(reference);
      if (validatedReference == null) {
        throw const FormatException('文件已缺失或不再位于当前项目内。');
      }
      if (!mounted || revision != _loadRevision) return;
      _reference = validatedReference;
      final file = File(validatedReference.path);
      if (await file.length() > maximumMarkdownBytes) {
        throw const FormatException('文件超过 8 MB，无法在应用内预览。');
      }
      final content = await file.readAsString();
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _loading = false;
        _content = content;
        _sourceLines = content.split('\n');
      });
      _resetScrollPositions();
    } catch (error) {
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  void _resetScrollPositions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_previewController.hasClients) _previewController.jumpTo(0);
      if (_sourceHorizontalController.hasClients) {
        _sourceHorizontalController.jumpTo(0);
      }
      _scrollToSourceLocation();
    });
  }

  void _scrollToSourceLocation() {
    if (_mode != MarkdownViewMode.source || !_sourceController.hasClients) {
      return;
    }
    final line = _reference.line;
    if (line == null) {
      _sourceController.jumpTo(0);
      return;
    }
    final target = math.max(0, line - 1) * sourceLineExtent;
    _sourceController.jumpTo(
      target.clamp(0.0, _sourceController.position.maxScrollExtent),
    );
  }

  void _setMode(MarkdownViewMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (mode == MarkdownViewMode.source) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToSourceLocation();
      });
    }
  }

  Future<void> _goBack() async {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    await _load(previous);
  }

  Future<void> _openExternally() async {
    try {
      final reference = await _validatedReference(_reference);
      if (reference == null) {
        _showMessage('文件已缺失或不再位于当前项目内。');
        return;
      }
      final opened = await launchUrl(
        reference.uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _showMessage('无法在默认应用中打开此文档。');
    } catch (_) {
      _showMessage('无法在默认应用中打开此文档。');
    }
  }

  Future<WorkspaceFileReference?> _validatedReference(
    WorkspaceFileReference reference,
  ) async {
    final resolved = await resolveWorkspaceFileReference(
      href: reference.uri.toString(),
      workspacePath: widget.workspacePath,
    );
    if (resolved == null) return null;
    return WorkspaceFileReference(
      uri: resolved.uri,
      line: reference.line,
      column: reference.column,
    );
  }

  Future<void> _handleLink(String? href) async {
    if (href == null || href.trim().isEmpty) return;
    final value = href.trim();
    final uri = Uri.tryParse(value);
    if (uri != null &&
        const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase())) {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened) _showMessage('无法打开此链接。');
      } catch (_) {
        _showMessage('无法打开此链接。');
      }
      return;
    }
    if (value.startsWith('#')) return;

    final reference = await resolveWorkspaceFileReference(
      href: value,
      workspacePath: widget.workspacePath,
      relativeToDirectoryPath: File(_reference.path).parent.path,
    );
    if (!mounted) return;
    if (reference == null) {
      _showMessage('无法打开此链接或项目内文件。');
      return;
    }
    if (isMarkdownFilePath(reference.path)) {
      _history.add(_reference);
      await _load(reference);
      return;
    }
    try {
      final opened = await launchUrl(
        reference.uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _showMessage('无法在默认应用中打开此文件。');
    } catch (_) {
      _showMessage('无法在默认应用中打开此文件。');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _fileName {
    final segments = _reference.uri.pathSegments;
    return segments.isEmpty ? _reference.path : segments.last;
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: 'Markdown 文档预览',
          child: SafeArea(
            minimum: const EdgeInsets.all(18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1120,
                  maxHeight: 860,
                ),
                child: Container(
                  key: const Key('markdown-preview-dialog'),
                  width: double.infinity,
                  height: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: palette.module,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 36,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildHeader(palette),
                      Divider(height: 1, color: palette.border),
                      Expanded(child: _buildBody(palette)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(YeknomPalette palette) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final modes = MarkdownModeSwitch(mode: _mode, onChanged: _setMode);
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 10, compact ? 10 : 9),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('markdown-preview-back-button'),
                    tooltip: _history.isEmpty ? '没有上一份文档' : '返回上一份文档',
                    onPressed: _history.isEmpty ? null : _goBack,
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _fileName,
                                key: const Key('markdown-preview-file-name'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_reference.line case final line?) ...[
                              const SizedBox(width: 8),
                              LocationLabel(
                                line: line,
                                column: _reference.column,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Tooltip(
                          message: _reference.path,
                          child: Text(
                            _reference.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[const SizedBox(width: 16), modes],
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('markdown-preview-external-button'),
                    tooltip: '在默认应用中打开',
                    onPressed: _openExternally,
                    icon: const Icon(Icons.open_in_new, size: 20),
                  ),
                  IconButton(
                    key: const Key('markdown-preview-close-button'),
                    tooltip: '关闭预览',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 21),
                  ),
                ],
              ),
              if (compact) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: modes),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(YeknomPalette palette) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.active,
          ),
        ),
      );
    }
    if (_loadError != null) {
      final message = _loadError is FormatException
          ? (_loadError as FormatException).message
          : '文档读取失败，文件可能已被移动或编码不受支持。';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 38, color: palette.muted),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => unawaited(_load(_reference)),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新载入'),
              ),
            ],
          ),
        ),
      );
    }
    return switch (_mode) {
      MarkdownViewMode.preview => _buildPreview(palette),
      MarkdownViewMode.source => _buildSource(palette),
    };
  }

  Widget _buildPreview(YeknomPalette palette) {
    final content = _content ?? '';
    final theme = Theme.of(context);
    return Scrollbar(
      controller: _previewController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: const Key('markdown-preview-scroll-view'),
        controller: _previewController,
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 64),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: MarkdownBody(
              key: ValueKey('markdown-preview-content-${_reference.path}'),
              data: content,
              selectable: true,
              onTapLink: (_, href, _) => unawaited(_handleLink(href)),
              imageBuilder: (uri, title, alt) => WorkspaceMarkdownImage(
                source: uri.toString(),
                alt: alt,
                workspacePath: widget.workspacePath,
                documentDirectoryPath: File(_reference.path).parent.path,
              ),
              styleSheet: markdownStyle(theme, palette),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSource(YeknomPalette palette) {
    final longestLine = _sourceLines.fold<int>(
      0,
      (longest, line) => math.max(longest, _sourceLineDisplayLength(line)),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(
          constraints.maxWidth,
          76 + (longestLine * 7.8),
        );
        return Scrollbar(
          controller: _sourceHorizontalController,
          notificationPredicate: (notification) => notification.depth == 0,
          child: SingleChildScrollView(
            key: const Key('markdown-source-horizontal-scroll'),
            controller: _sourceHorizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              key: const Key('markdown-source-content'),
              width: contentWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: _sourceController,
                thumbVisibility: true,
                child: ListView.builder(
                  key: const Key('markdown-source-view'),
                  controller: _sourceController,
                  itemExtent: sourceLineExtent,
                  itemCount: _sourceLines.length,
                  itemBuilder: (context, index) {
                    final lineNumber = index + 1;
                    final selected = lineNumber == _reference.line;
                    return ColoredBox(
                      key: ValueKey('markdown-source-line-$lineNumber'),
                      color: selected
                          ? palette.active.withValues(alpha: 0.12)
                          : Colors.transparent,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 62,
                            child: Text(
                              '$lineNumber',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: selected
                                    ? palette.active
                                    : palette.faint,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: SelectableText(
                              _sourceLinePreview(_sourceLines[index]),
                              maxLines: 1,
                              style: TextStyle(
                                height: 1.35,
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: palette.trace,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _sourceLineDisplayLength(String line) {
    if (line.isEmpty) return 1;
    if (line.length <= maximumRenderedSourceLineCharacters) {
      return line.length;
    }
    return maximumRenderedSourceLineCharacters +
        ' $truncatedSourceLineMessage（共 ${line.length} 个字符）'.length;
  }

  String _sourceLinePreview(String line) {
    if (line.isEmpty) return ' ';
    if (line.length <= maximumRenderedSourceLineCharacters) return line;
    var end = maximumRenderedSourceLineCharacters;
    if (_splitsSurrogatePair(line, end)) end--;
    return '${line.substring(0, end)} $truncatedSourceLineMessage（共 ${line.length} 个字符）';
  }

  bool _splitsSurrogatePair(String value, int index) {
    if (index <= 0 || index >= value.length) return false;
    final previous = value.codeUnitAt(index - 1);
    final next = value.codeUnitAt(index);
    return previous >= 0xD800 &&
        previous <= 0xDBFF &&
        next >= 0xDC00 &&
        next <= 0xDFFF;
  }
}
