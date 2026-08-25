import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

import '../services/agent_markdown_link.dart';

const _maximumMarkdownBytes = 8 * 1024 * 1024;
const _sourceLineExtent = 24.0;
const _maximumRenderedSourceLineCharacters = 4096;
const _truncatedSourceLineMessage = '… 此行过长，已截断显示';

enum _MarkdownViewMode { preview, source }

/// Opens a project-local Markdown document without leaving the workbench.
Future<void> showWorkspaceMarkdownPreview(
  BuildContext context, {
  required WorkspaceFileReference reference,
  required String workspacePath,
}) async {
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭 Markdown 预览',
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _WorkspaceMarkdownPreview(
          reference: reference,
          workspacePath: workspacePath,
        ),
  );
}

class _WorkspaceMarkdownPreview extends StatefulWidget {
  const _WorkspaceMarkdownPreview({
    required this.reference,
    required this.workspacePath,
  });

  final WorkspaceFileReference reference;
  final String workspacePath;

  @override
  State<_WorkspaceMarkdownPreview> createState() =>
      _WorkspaceMarkdownPreviewState();
}

class _WorkspaceMarkdownPreviewState extends State<_WorkspaceMarkdownPreview> {
  final ScrollController _previewController = ScrollController();
  final ScrollController _sourceController = ScrollController();
  final ScrollController _sourceHorizontalController = ScrollController();
  final List<WorkspaceFileReference> _history = [];

  late WorkspaceFileReference _reference;
  _MarkdownViewMode _mode = _MarkdownViewMode.preview;
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
      final file = File(reference.path);
      if (await file.length() > _maximumMarkdownBytes) {
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
    if (_mode != _MarkdownViewMode.source || !_sourceController.hasClients) {
      return;
    }
    final line = _reference.line;
    if (line == null) {
      _sourceController.jumpTo(0);
      return;
    }
    final target = math.max(0, line - 1) * _sourceLineExtent;
    _sourceController.jumpTo(
      target.clamp(0.0, _sourceController.position.maxScrollExtent),
    );
  }

  void _setMode(_MarkdownViewMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (mode == _MarkdownViewMode.source) {
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
      final opened = await launchUrl(
        _reference.uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _showMessage('无法在默认应用中打开此文档。');
    } catch (_) {
      _showMessage('无法在默认应用中打开此文档。');
    }
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
        final modes = _MarkdownModeSwitch(mode: _mode, onChanged: _setMode);
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
                              _LocationLabel(
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
      _MarkdownViewMode.preview => _buildPreview(palette),
      _MarkdownViewMode.source => _buildSource(palette),
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
              imageBuilder: (uri, title, alt) => _WorkspaceMarkdownImage(
                source: uri.toString(),
                alt: alt,
                workspacePath: widget.workspacePath,
                documentDirectoryPath: File(_reference.path).parent.path,
              ),
              styleSheet: _markdownStyle(theme, palette),
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
                  itemExtent: _sourceLineExtent,
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
    if (line.length <= _maximumRenderedSourceLineCharacters) {
      return line.length;
    }
    return _maximumRenderedSourceLineCharacters +
        ' $_truncatedSourceLineMessage（共 ${line.length} 个字符）'.length;
  }

  String _sourceLinePreview(String line) {
    if (line.isEmpty) return ' ';
    if (line.length <= _maximumRenderedSourceLineCharacters) return line;
    var end = _maximumRenderedSourceLineCharacters;
    if (_splitsSurrogatePair(line, end)) end--;
    return '${line.substring(0, end)} $_truncatedSourceLineMessage（共 ${line.length} 个字符）';
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

class _MarkdownModeSwitch extends StatelessWidget {
  const _MarkdownModeSwitch({required this.mode, required this.onChanged});

  final _MarkdownViewMode mode;
  final ValueChanged<_MarkdownViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeButton(
              key: const Key('markdown-preview-mode-button'),
              label: '预览',
              selected: mode == _MarkdownViewMode.preview,
              onPressed: () => onChanged(_MarkdownViewMode.preview),
            ),
            _ModeButton(
              key: const Key('markdown-source-mode-button'),
              label: '源码',
              selected: mode == _MarkdownViewMode.source,
              onPressed: () => onChanged(_MarkdownViewMode.source),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(54, 28),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: selected ? palette.trace : palette.muted,
        backgroundColor: selected ? palette.selected : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _LocationLabel extends StatelessWidget {
  const _LocationLabel({required this.line, required this.column});

  final int line;
  final int? column;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.active.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          column == null ? 'L$line' : 'L$line:C$column',
          style: TextStyle(
            color: palette.active,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceMarkdownImage extends StatelessWidget {
  const _WorkspaceMarkdownImage({
    required this.source,
    required this.alt,
    required this.workspacePath,
    required this.documentDirectoryPath,
  });

  final String source;
  final String? alt;
  final String workspacePath;
  final String documentDirectoryPath;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(source);
    if (uri != null &&
        const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      final description = alt?.trim();
      return _ImageFallback(
        label: description == null || description.isEmpty
            ? '远程图片未自动载入'
            : '远程图片未自动载入：$description',
      );
    }
    return FutureBuilder<WorkspaceFileReference?>(
      future: resolveWorkspaceFileReference(
        href: source,
        workspacePath: workspacePath,
        relativeToDirectoryPath: documentDirectoryPath,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final reference = snapshot.data;
        if (reference == null) return _ImageFallback(label: alt ?? '图片不可用');
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(reference.path),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _ImageFallback(label: alt ?? '图片不可用'),
            ),
          ),
        );
      },
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 18,
            color: palette.muted,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, style: TextStyle(color: palette.muted)),
          ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet _markdownStyle(ThemeData theme, YeknomPalette palette) {
  final body = theme.textTheme.bodyMedium?.copyWith(
    color: palette.trace,
    fontSize: 15,
    height: 1.65,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    pPadding: const EdgeInsets.only(bottom: 4),
    h1: body?.copyWith(fontSize: 30, height: 1.25, fontWeight: FontWeight.w600),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 14),
    h2: body?.copyWith(fontSize: 23, height: 1.3, fontWeight: FontWeight.w600),
    h2Padding: const EdgeInsets.only(top: 18, bottom: 10),
    h3: body?.copyWith(fontSize: 18, height: 1.35, fontWeight: FontWeight.w600),
    h3Padding: const EdgeInsets.only(top: 14, bottom: 7),
    blockSpacing: 10,
    listIndent: 24,
    listBullet: body,
    a: body?.copyWith(
      color: palette.active,
      decoration: TextDecoration.underline,
      decorationColor: palette.active.withValues(alpha: 0.6),
    ),
    code: body?.copyWith(
      color: palette.trace,
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.5,
      backgroundColor: palette.field,
    ),
    codeblockPadding: const EdgeInsets.all(14),
    codeblockDecoration: BoxDecoration(
      color: palette.field,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: palette.border),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    blockquoteDecoration: BoxDecoration(
      color: palette.raised,
      border: Border(left: BorderSide(color: palette.active, width: 3)),
    ),
    tableBorder: TableBorder.all(color: palette.border),
    tableHead: body?.copyWith(fontWeight: FontWeight.w700),
    tableBody: body,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: palette.border)),
    ),
  );
}
