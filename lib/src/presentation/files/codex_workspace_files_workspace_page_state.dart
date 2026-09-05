import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/presentation/files/codex_workspace_file_entry.dart';
import 'package:chatgpt/src/presentation/files/codex_workspace_files_workspace_page.dart';
import 'package:chatgpt/src/presentation/files/workspace_code_syntax_highlighter.dart';
import 'package:chatgpt/src/presentation/files/workspace_file_preview_reader.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Owns the directory expansion, filtering and refresh lifecycle for files.
class FilesWorkspacePageState extends State<FilesWorkspacePage> {
  final TextEditingController _filter = TextEditingController();
  final FocusNode _filterFocus = FocusNode(debugLabel: 'files-filter');
  final Map<String, List<CodexWorkspaceFileEntry>> _children = {};
  final Set<String> _expanded = {};
  final Set<String> _loading = {};
  String? _selectedPath;
  String? _selectedFileContent;
  String? _selectedFileError;
  TextSpan? _selectedFileHighlight;
  String? _highlightedPath;
  bool? _highlightedDark;
  bool _isSelectedFileLoading = false;
  String? _error;
  int _loadGeneration = 0;
  int _fileReadGeneration = 0;

  static const int _maximumPreviewBytes = 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _filter.addListener(_handleFilterChanged);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant FilesWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible && !widget.isVisible) _filterFocus.unfocus();
    if (oldWidget.workspacePath != widget.workspacePath) unawaited(_reload());
  }

  @override
  void dispose() {
    _filter
      ..removeListener(_handleFilterChanged)
      ..dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  void _handleFilterChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final workspace = widget.workspacePath;
    final generation = ++_loadGeneration;
    _fileReadGeneration++;
    setState(() {
      _children.clear();
      _expanded.clear();
      _loading.clear();
      _selectedPath = null;
      _selectedFileContent = null;
      _selectedFileError = null;
      _clearHighlightCache();
      _isSelectedFileLoading = false;
      _error = null;
    });
    if (workspace == null || workspace.isEmpty) return;
    await _loadChildren(workspace, generation: generation);
  }

  Future<void> _loadChildren(String path, {int? generation}) async {
    final requestGeneration = generation ?? _loadGeneration;
    if (_loading.contains(path) || _children.containsKey(path)) return;
    setState(() => _loading.add(path));
    try {
      final directory = Directory(path);
      final items = await directory.list(followLinks: false).toList();
      final entries =
          items.map(CodexWorkspaceFileEntry.fromFileSystemEntity).toList()
            ..sort((left, right) {
              if (left.isDirectory != right.isDirectory) {
                return left.isDirectory ? -1 : 1;
              }
              return left.name.toLowerCase().compareTo(
                right.name.toLowerCase(),
              );
            });
      if (!mounted || requestGeneration != _loadGeneration) return;
      setState(() => _children[path] = entries);
    } on FileSystemException {
      if (!mounted || requestGeneration != _loadGeneration) return;
      setState(() => _error = '无法读取此工作区的文件。');
    } finally {
      if (mounted && requestGeneration == _loadGeneration) {
        setState(() => _loading.remove(path));
      }
    }
  }

  void _toggleDirectory(CodexWorkspaceFileEntry entry) {
    if (_expanded.remove(entry.path)) {
      setState(() {});
      return;
    }
    setState(() => _expanded.add(entry.path));
    unawaited(_loadChildren(entry.path));
  }

  Future<void> _selectFile(CodexWorkspaceFileEntry entry) async {
    final workspace = widget.workspacePath;
    if (workspace == null || workspace.isEmpty) return;
    final generation = ++_fileReadGeneration;
    setState(() {
      _selectedPath = entry.path;
      _selectedFileContent = null;
      _selectedFileError = null;
      _clearHighlightCache();
      _isSelectedFileLoading = true;
    });
    try {
      final preview = await WorkspaceFilePreviewReader(
        workspacePath: workspace,
        maximumBytes: _maximumPreviewBytes,
      ).read(entry.path);
      if (!mounted || generation != _fileReadGeneration) return;
      setState(() {
        _selectedFileContent = preview.content;
        _selectedFileError = preview.error;
        _isSelectedFileLoading = false;
      });
    } on Object {
      if (!mounted || generation != _fileReadGeneration) return;
      setState(() {
        _selectedFileError = '无法读取此文件。';
        _isSelectedFileLoading = false;
      });
    }
  }

  void _clearHighlightCache() {
    _selectedFileHighlight = null;
    _highlightedPath = null;
    _highlightedDark = null;
  }

  TextSpan _highlightedContent({
    required String content,
    required String path,
    required bool dark,
  }) {
    if (_selectedFileHighlight != null &&
        _highlightedPath == path &&
        _highlightedDark == dark) {
      return _selectedFileHighlight!;
    }
    final highlight = WorkspaceCodeSyntaxHighlighter(
      dark: dark,
    ).highlight(content: content, path: path);
    _selectedFileHighlight = highlight;
    _highlightedPath = path;
    _highlightedDark = dark;
    return highlight;
  }

  bool _matchesFilter(CodexWorkspaceFileEntry entry) {
    final query = _filter.text.trim().toLowerCase();
    return entry.matchesNameQuery(query);
  }

  String _displayPath(String path) {
    final root = widget.workspacePath;
    if (root == null || !path.startsWith(root)) return path;
    final relative = path
        .substring(root.length)
        .replaceFirst(RegExp(r'^/'), '');
    return relative.isEmpty ? '/' : relative;
  }

  Widget _buildTree(String directory, int depth, YeknomPalette palette) {
    final entries = _children[directory] ?? const <CodexWorkspaceFileEntry>[];
    if (_loading.contains(directory) && entries.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: 16.0 + depth * 14, top: 10),
        child: SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: palette.muted,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          if (_matchesFilter(entry)) ...[
            Material(
              color: _selectedPath == entry.path
                  ? palette.selected
                  : Colors.transparent,
              child: InkWell(
                key: ValueKey('files-entry-${entry.path}'),
                onTap: entry.isDirectory
                    ? () => _toggleDirectory(entry)
                    : () => unawaited(_selectFile(entry)),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 10 + depth * 14,
                    right: 8,
                    top: 5,
                    bottom: 5,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: entry.isDirectory
                            ? Icon(
                                _expanded.contains(entry.path)
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_right,
                                size: 16,
                                color: palette.muted,
                              )
                            : Icon(
                                Icons.insert_drive_file_outlined,
                                size: 15,
                                color: palette.muted,
                              ),
                      ),
                      Icon(
                        entry.isDirectory
                            ? Icons.folder_outlined
                            : Icons.description_outlined,
                        size: 15,
                        color: entry.isDirectory
                            ? palette.signal
                            : palette.muted,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: palette.trace),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (entry.isDirectory && _expanded.contains(entry.path))
              _buildTree(entry.path, depth + 1, palette),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final workspace = widget.workspacePath;
    final selectedPath = _selectedPath;
    return Column(
      children: [
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: palette.bench,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_copy_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  workspace == null ? '文件' : _displayPath(workspace),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.trace),
                ),
              ),
              IconButton(
                key: const Key('files-refresh'),
                tooltip: '刷新文件',
                onPressed: () => unawaited(_reload()),
                icon: const Icon(Icons.refresh, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: workspace == null
              ? _buildEmptyState(palette, '尚未打开工作区', '选择一个项目文件夹后即可浏览文件。')
              : Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: selectedPath == null
                          ? _buildEmptyState(palette, '打开文件', '从工作区目录树中选择文件')
                          : _buildSelection(palette, selectedPath),
                    ),
                    Container(width: 1, color: palette.border),
                    SizedBox(
                      width: 236,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: TextField(
                              key: const Key('files-filter'),
                              controller: _filter,
                              focusNode: _filterFocus,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: '筛选文件…',
                                prefixIcon: const Icon(Icons.search, size: 16),
                                filled: true,
                                fillColor: palette.field,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: palette.border),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _error != null
                                ? Center(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(color: palette.muted),
                                    ),
                                  )
                                : ListView(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    children: [
                                      _buildTree(workspace, 0, palette),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(YeknomPalette palette, String title, String detail) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined, size: 34, color: palette.muted),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.trace,
              ),
            ),
            const SizedBox(height: 6),
            Text(detail, style: TextStyle(fontSize: 12, color: palette.muted)),
          ],
        ),
      );

  Widget _buildSelection(YeknomPalette palette, String path) {
    if (_isSelectedFileLoading) {
      return Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: palette.muted,
          ),
        ),
      );
    }
    final error = _selectedFileError;
    if (error != null) {
      return _buildEmptyState(palette, error, _displayPath(path));
    }
    final content = _selectedFileContent;
    if (content == null) {
      return _buildEmptyState(palette, '无法预览文件', _displayPath(path));
    }
    final lineCount = '\n'.allMatches(content).length + 1;
    final lineNumbers = List<String>.generate(
      lineCount,
      (index) => '${index + 1}',
    ).join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Text(
            _displayPath(path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lineNumbers,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 12,
                      height: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 14),
                  SelectableText.rich(
                    _highlightedContent(
                      content: content,
                      path: path,
                      dark: palette.dark,
                    ),
                    key: const Key('files-content'),
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
          ),
        ),
      ],
    );
  }
}
