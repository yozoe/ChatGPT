import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../domain/git_project_status.dart';
import '../theme/yeknom_workbench.dart';

/// Data source displayed by the workbench review surface.
enum CodeReviewSource { latestTurn, gitWorkspace }

extension CodeReviewSourceLabel on CodeReviewSource {
  String get label => switch (this) {
    CodeReviewSource.latestTurn => '最新一轮',
    CodeReviewSource.gitWorkspace => 'Git 工作区',
  };
}

/// Codex-style code review surface embedded in the active workbench.
class CodeReviewPanel extends StatefulWidget {
  const CodeReviewPanel({
    required this.controller,
    required this.source,
    required this.compact,
    required this.onSourceChanged,
    required this.onClose,
    super.key,
  });

  final CodexController controller;
  final CodeReviewSource source;
  final bool compact;
  final ValueChanged<CodeReviewSource> onSourceChanged;
  final VoidCallback onClose;

  @override
  State<CodeReviewPanel> createState() => _CodeReviewPanelState();
}

class _CodeReviewPanelState extends State<CodeReviewPanel> {
  static const _navigationRowExtent = 30.0;
  final TextEditingController _search = TextEditingController();
  final FocusNode _panelFocus = FocusNode(debugLabel: 'code-review-panel');
  final ScrollController _navigationController = ScrollController();
  final Map<CodeReviewSource, ScrollController> _horizontal = {
    for (final source in CodeReviewSource.values) source: ScrollController(),
  };
  final Map<CodeReviewSource, ScrollController> _vertical = {
    for (final source in CodeReviewSource.values) source: ScrollController(),
  };
  final Map<CodeReviewSource, String> _queries = {
    for (final source in CodeReviewSource.values) source: '',
  };
  final Map<CodeReviewSource, String?> _selectedPaths = {
    for (final source in CodeReviewSource.values) source: null,
  };
  final Map<String, GlobalKey> _headerKeys = {};
  final Map<String, GlobalKey> _navigationKeys = {};
  final Set<String> _collapsedDirectories = {};
  final GlobalKey _canvasKey = GlobalKey();
  bool _navigationVisible = true;
  bool _navigationOverlayOpen = false;
  bool _scrollInspectionScheduled = false;
  String? _programmaticScrollPath;
  String? _gitOperationPath;
  String? _workspaceIdentity;
  String? _threadIdentity;

  ScrollController get _verticalController => _vertical[widget.source]!;
  ScrollController get _horizontalController => _horizontal[widget.source]!;

  @override
  void initState() {
    super.initState();
    _workspaceIdentity = widget.controller.workspacePath;
    _threadIdentity = widget.controller.activeThreadId;
    for (final controller in _vertical.values) {
      controller.addListener(_scheduleVisibleFileInspection);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _panelFocus.requestFocus();
      _ensureInitialData();
    });
  }

  @override
  void didUpdateWidget(covariant CodeReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _queries[oldWidget.source] = _search.text;
      _search.text = _queries[widget.source] ?? '';
      _navigationOverlayOpen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureSelectedFile(_filesForSource());
      });
    }
    final workspace = widget.controller.workspacePath;
    if (_workspaceIdentity != workspace) {
      _workspaceIdentity = workspace;
      _threadIdentity = widget.controller.activeThreadId;
      _resetSourceState(CodeReviewSource.latestTurn);
      _resetSourceState(CodeReviewSource.gitWorkspace);
      _collapsedDirectories.clear();
      _headerKeys.clear();
      _navigationKeys.clear();
    } else if (_threadIdentity != widget.controller.activeThreadId) {
      _threadIdentity = widget.controller.activeThreadId;
      _resetSourceState(CodeReviewSource.latestTurn);
    }
  }

  void _resetSourceState(CodeReviewSource source) {
    _queries[source] = '';
    _selectedPaths[source] = null;
    if (widget.source == source) _search.clear();
    final controller = _vertical[source]!;
    if (controller.hasClients) controller.jumpTo(0);
  }

  @override
  void dispose() {
    _search.dispose();
    _panelFocus.dispose();
    _navigationController.dispose();
    for (final controller in _horizontal.values) {
      controller.dispose();
    }
    for (final controller in _vertical.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _ensureInitialData() {
    if (!mounted) return;
    if (widget.source == CodeReviewSource.latestTurn) {
      unawaited(widget.controller.ensureFileChangeDiffs());
    } else if (!widget.controller.gitReviewLoading &&
        widget.controller.gitReviewDiffs.isEmpty) {
      unawaited(widget.controller.refreshGitReview());
    }
  }

  Future<void> _refresh() async {
    if (widget.source == CodeReviewSource.latestTurn) {
      await widget.controller.ensureFileChangeDiffs();
    } else {
      await widget.controller.refreshGitReview();
    }
  }

  void _selectSource(CodeReviewSource source) {
    if (source == widget.source) return;
    widget.onSourceChanged(source);
    if (source == CodeReviewSource.gitWorkspace) {
      unawaited(widget.controller.refreshGitReview());
    } else {
      unawaited(widget.controller.ensureFileChangeDiffs());
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_search.text.isNotEmpty) {
      setState(() {
        _search.clear();
        _queries[widget.source] = '';
      });
    } else if (_navigationOverlayOpen) {
      setState(() => _navigationOverlayOpen = false);
    } else {
      widget.onClose();
    }
    return KeyEventResult.handled;
  }

  List<_ReviewFile> _filesForSource() {
    if (widget.source == CodeReviewSource.latestTurn) {
      final changes = widget.controller.fileChanges;
      final files = [
        for (final change in changes)
          _ReviewFile(path: change.path, kind: change.kind, diff: change.diff),
      ];
      final fallback = widget.controller.turnDiff;
      if (files.isEmpty && fallback != null && fallback.trim().isNotEmpty) {
        files.add(_ReviewFile(path: '本次任务完整 Diff', kind: '任务', diff: fallback));
      } else if (files.any((file) => file.diff.trim().isEmpty) &&
          fallback != null &&
          fallback.trim().isNotEmpty) {
        files.add(_ReviewFile(path: '本次任务完整 Diff', kind: '任务', diff: fallback));
      }
      return files;
    }
    final status = widget.controller.gitProjectStatus;
    if (status == null) return const [];
    return [
      for (final change in status.changes)
        _ReviewFile(
          path: change.path,
          kind: change.label,
          diff: widget.controller.gitReviewDiffs[change.path]?.content ?? '',
          truncated:
              widget.controller.gitReviewDiffs[change.path]?.truncated ?? false,
          error: widget.controller.gitReviewDiffErrors[change.path],
          gitChange: change,
        ),
    ];
  }

  List<_ReviewFile> _filteredFiles(List<_ReviewFile> files) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return files;
    return files
        .where((file) => file.path.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _ensureSelectedFile(List<_ReviewFile> files) {
    final selected = _selectedPaths[widget.source];
    if (files.isEmpty) {
      if (selected != null) {
        setState(() => _selectedPaths[widget.source] = null);
      }
      return;
    }
    if (selected == null || !files.any((file) => file.path == selected)) {
      setState(() => _selectedPaths[widget.source] = files.first.path);
    }
  }

  void _jumpToFile(String path) {
    setState(() {
      _selectedPaths[widget.source] = path;
      _navigationOverlayOpen = false;
    });
    _programmaticScrollPath = path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _headerKeys[path]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: Duration.zero,
          alignment: 0,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _programmaticScrollPath == path) {
          _programmaticScrollPath = null;
        }
      });
    });
  }

  void _revealNavigationPath(String path, {int remainingAttempts = 2}) {
    if (!_navigationController.hasClients) return;
    final rows = _treeRows(_filteredFiles(_filesForSource()));
    final index = rows.indexWhere((row) => row.file?.path == path);
    if (index < 0) return;
    final position = _navigationController.position;
    final top = index * _navigationRowExtent;
    final bottom = top + _navigationRowExtent;
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;
    final target = top < viewportTop
        ? top
        : bottom > viewportBottom
        ? bottom - position.viewportDimension
        : viewportTop;
    if (target != viewportTop) {
      _navigationController.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _navigationKeys[path]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, duration: Duration.zero);
      } else if (remainingAttempts > 0) {
        _revealNavigationPath(path, remainingAttempts: remainingAttempts - 1);
      }
    });
  }

  void _scheduleVisibleFileInspection() {
    if (_scrollInspectionScheduled) return;
    _scrollInspectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollInspectionScheduled = false;
      if (!mounted) return;
      if (_programmaticScrollPath != null) return;
      final canvasBox = _canvasKey.currentContext?.findRenderObject();
      if (canvasBox is! RenderBox || !canvasBox.hasSize) return;
      final viewportTop = canvasBox.localToGlobal(Offset.zero).dy + 38;
      String? nearest;
      var nearestDistance = double.infinity;
      for (final file in _filteredFiles(_filesForSource())) {
        final renderObject = _headerKeys[file.path]?.currentContext
            ?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.hasSize) continue;
        final top = renderObject.localToGlobal(Offset.zero).dy;
        final distance = top <= viewportTop
            ? (viewportTop - top) * 0.01
            : top - viewportTop;
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = file.path;
        }
      }
      if (nearest != null && _selectedPaths[widget.source] != nearest) {
        setState(() => _selectedPaths[widget.source] = nearest);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _revealNavigationPath(nearest!);
        });
      }
    });
  }

  Future<void> _stage(_ReviewFile file) async {
    final change = file.gitChange;
    if (change == null) return;
    setState(() => _gitOperationPath = file.path);
    try {
      final succeeded = await widget.controller.stageGitChange(change);
      if (succeeded) {
        await widget.controller.refreshGitReview();
      } else {
        _showGitOperationError('无法暂存“${file.path}”。');
      }
    } finally {
      if (mounted) setState(() => _gitOperationPath = null);
    }
  }

  Future<void> _revert(_ReviewFile file) async {
    final change = file.gitChange;
    if (change == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('还原文件改动？'),
        content: Text(
          change.isUntracked
              ? '“${change.path}”是未跟踪文件，还原会从磁盘删除它，无法恢复。'
              : '“${change.path}”的暂存区和工作区改动将被丢弃，无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('还原'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _gitOperationPath = file.path);
    try {
      final succeeded = await widget.controller.revertGitChange(change);
      if (succeeded) {
        await widget.controller.refreshGitReview();
      } else {
        _showGitOperationError('无法还原“${file.path}”。');
      }
    } finally {
      if (mounted) setState(() => _gitOperationPath = null);
    }
  }

  Future<void> _commitOrPush() async {
    final message = TextEditingController();
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提交或推送'),
        content: TextField(
          controller: message,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(labelText: '提交消息'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('仅提交'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('提交并推送'),
          ),
        ],
      ),
    );
    final text = message.text.trim();
    message.dispose();
    if (action == null || text.isEmpty) return;
    final committed = await widget.controller.commitGitChanges(text);
    if (!committed) {
      _showGitOperationError('无法提交当前改动。');
      return;
    }
    var pushed = true;
    if (action) pushed = await widget.controller.pushGitBranch();
    await widget.controller.refreshGitReview();
    if (!pushed) {
      _showGitOperationError('提交已经创建，但无法推送当前分支。');
    }
  }

  Future<void> _createPullRequest() async {
    final title = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建拉取请求'),
        content: TextField(
          controller: title,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(labelText: '拉取请求标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final value = title.text.trim();
    title.dispose();
    if (confirmed == true && value.isNotEmpty) {
      final created = await widget.controller.createGitPullRequest(value);
      if (!created) _showGitOperationError('无法创建拉取请求。');
    }
  }

  void _showGitOperationError(String fallback) {
    if (!mounted) return;
    final message = widget.controller.gitOperationError ?? fallback;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleNavigation() {
    final renderObject = context.findRenderObject();
    final panelWidth = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.size.width
        : 0.0;
    setState(() {
      if (!widget.compact && panelWidth >= 740) {
        _navigationVisible = !_navigationVisible;
        _navigationOverlayOpen = false;
      } else {
        _navigationVisible = true;
        _navigationOverlayOpen = !_navigationOverlayOpen;
      }
    });
    if (_navigationOverlayOpen) {
      final selected = _selectedPaths[widget.source];
      if (selected != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _revealNavigationPath(selected);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final files = _filesForSource();
    final filtered = _filteredFiles(files);
    final selected = _selectedPaths[widget.source];
    if (files.isNotEmpty &&
        (selected == null || !files.any((file) => file.path == selected))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureSelectedFile(files);
      });
    }
    final stats = files.fold(
      const _ReviewStats(),
      (total, file) => total + _reviewStats(file.diff),
    );
    final unknown = files.any(
      (file) => file.diff.trim().isEmpty || file.error != null,
    );
    final fileCount = widget.source == CodeReviewSource.latestTurn
        ? widget.controller.fileChanges.length
        : widget.controller.gitProjectStatus?.changes.length ?? 0;
    return Focus(
      focusNode: _panelFocus,
      autofocus: widget.compact,
      onKeyEvent: _handleKey,
      child: Material(
        key: const Key('code-review-panel'),
        color: palette.bench,
        child: Column(
          children: [
            _buildTitleBar(context, palette),
            Divider(height: 1, color: palette.border),
            _buildToolbar(context, palette, stats, unknown, fileCount),
            Divider(height: 1, color: palette.border),
            if (selected != null)
              SizedBox.shrink(
                key: ValueKey('code-review-selected-path-$selected'),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final inlineNavigation =
                      !widget.compact &&
                      constraints.maxWidth >= 740 &&
                      _navigationVisible;
                  return Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildBody(context, palette, files)),
                          if (inlineNavigation) ...[
                            VerticalDivider(width: 1, color: palette.border),
                            SizedBox(
                              width: 240,
                              child: _buildNavigation(
                                context,
                                palette,
                                filtered,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (!inlineNavigation && _navigationOverlayOpen)
                        Positioned.fill(
                          child: GestureDetector(
                            key: const Key('review-navigation-scrim'),
                            onTap: () =>
                                setState(() => _navigationOverlayOpen = false),
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.22),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: GestureDetector(
                                  onTap: () {},
                                  child: Container(
                                    key: const Key('review-navigation-overlay'),
                                    width: math.min(280, constraints.maxWidth),
                                    decoration: BoxDecoration(
                                      color: palette.module,
                                      border: Border(
                                        left: BorderSide(color: palette.border),
                                      ),
                                    ),
                                    child: _buildNavigation(
                                      context,
                                      palette,
                                      filtered,
                                    ),
                                  ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context, YeknomPalette palette) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 8),
          if (widget.compact)
            IconButton(
              key: const Key('code-review-back'),
              tooltip: '返回会话',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: widget.onClose,
              icon: const Icon(Icons.arrow_back, size: 17),
            )
          else
            Icon(Icons.edit_note_outlined, size: 17, color: palette.muted),
          const SizedBox(width: 7),
          Text(
            '审查',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            key: const Key('code-review-close'),
            tooltip: '关闭审查',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 17),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    YeknomPalette palette,
    _ReviewStats stats,
    bool unknown,
    int fileCount,
  ) {
    final workspace = widget.controller.workspacePath;
    final repository = workspace == null
        ? '未选项目'
        : workspace.split('/').where((part) => part.isNotEmpty).lastOrNull ??
              workspace;
    return SizedBox(
      height: 42,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactToolbar = constraints.maxWidth < 620;
          final hideStats = constraints.maxWidth < 340;
          final hideFileCount = constraints.maxWidth < 430;
          const iconConstraints = BoxConstraints.tightFor(
            width: 36,
            height: 36,
          );
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: compactToolbar ? 6 : 10),
            child: Row(
              children: [
                if (!compactToolbar) ...[
                  Flexible(
                    child: Text(
                      repository,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.trace, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                PopupMenuButton<CodeReviewSource>(
                  key: const Key('code-review-source-menu'),
                  tooltip: '变更来源',
                  initialValue: widget.source,
                  onSelected: _selectSource,
                  itemBuilder: (context) => [
                    for (final source in CodeReviewSource.values)
                      PopupMenuItem(value: source, child: Text(source.label)),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.source.label,
                        style: TextStyle(color: palette.trace, fontSize: 12),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.expand_more, size: 16, color: palette.muted),
                    ],
                  ),
                ),
                if (!hideStats) ...[
                  SizedBox(width: compactToolbar ? 8 : 12),
                  Text(
                    unknown ? '+?' : '+${stats.additions}',
                    key: const Key('code-review-additions'),
                    style: TextStyle(color: palette.ack, fontSize: 12),
                  ),
                  SizedBox(width: compactToolbar ? 5 : 7),
                  Text(
                    unknown ? '-?' : '-${stats.deletions}',
                    key: const Key('code-review-deletions'),
                    style: TextStyle(color: palette.fault, fontSize: 12),
                  ),
                ],
                if (!hideFileCount) ...[
                  const SizedBox(width: 10),
                  Text(
                    '$fileCount 个文件',
                    key: const Key('code-review-file-count'),
                    style: TextStyle(color: palette.muted, fontSize: 11),
                  ),
                ],
                const Spacer(),
                if (widget.source == CodeReviewSource.gitWorkspace &&
                    !compactToolbar)
                  IconButton(
                    key: const Key('code-review-commit'),
                    tooltip: '提交或推送',
                    padding: EdgeInsets.zero,
                    constraints: iconConstraints,
                    onPressed: widget.controller.gitOperationRunning
                        ? null
                        : _commitOrPush,
                    icon: const Icon(Icons.upload_outlined, size: 17),
                  ),
                if (widget.source == CodeReviewSource.gitWorkspace)
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: PopupMenuButton<String>(
                      key: const Key('code-review-more-menu'),
                      tooltip: '更多 Git 操作',
                      padding: EdgeInsets.zero,
                      enabled: !widget.controller.gitOperationRunning,
                      onSelected: (value) {
                        if (value == 'commit') {
                          unawaited(_commitOrPush());
                        } else if (value == 'pull-request') {
                          unawaited(_createPullRequest());
                        }
                      },
                      itemBuilder: (context) => [
                        if (compactToolbar)
                          const PopupMenuItem(
                            value: 'commit',
                            child: Text('提交或推送'),
                          ),
                        const PopupMenuItem(
                          value: 'pull-request',
                          child: Text('创建拉取请求'),
                        ),
                      ],
                      icon: const Icon(Icons.more_horiz, size: 17),
                    ),
                  ),
                IconButton(
                  key: const Key('code-review-refresh'),
                  tooltip: '刷新审查',
                  padding: EdgeInsets.zero,
                  constraints: iconConstraints,
                  onPressed:
                      widget.controller.gitReviewLoading ||
                          widget.controller.gitOperationRunning
                      ? null
                      : _refresh,
                  icon: const Icon(Icons.refresh, size: 17),
                ),
                IconButton(
                  key: const Key('code-review-navigation-toggle'),
                  tooltip: '文件导航',
                  padding: EdgeInsets.zero,
                  constraints: iconConstraints,
                  onPressed: _toggleNavigation,
                  icon: const Icon(Icons.account_tree_outlined, size: 17),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    YeknomPalette palette,
    List<_ReviewFile> files,
  ) {
    if (widget.source == CodeReviewSource.gitWorkspace) {
      if (widget.controller.gitReviewLoading && files.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (widget.controller.gitProjectError case final error?) {
        return _ReviewMessage(
          icon: Icons.error_outline,
          message: error,
          actionLabel: '重试',
          onAction: _refresh,
        );
      }
      final status = widget.controller.gitProjectStatus;
      if (status != null && !status.isRepository) {
        return const _ReviewMessage(
          icon: Icons.source_outlined,
          message: '当前项目不是 Git 仓库。',
        );
      }
    }
    if (files.isEmpty) {
      return _ReviewMessage(
        icon: Icons.check_circle_outline,
        message: widget.source == CodeReviewSource.latestTurn
            ? '当前任务没有可审查的文件变更。'
            : '当前工作区没有未提交变更。',
      );
    }
    final parsed = {
      for (final file in files) file.path: _parseReviewRows(file),
    };
    final maximumCharacters = files.fold<int>(0, (maximum, file) {
      final lines = file.diff.split('\n');
      final current = lines.fold<int>(
        0,
        (lineMaximum, line) => math.max(lineMaximum, line.length),
      );
      return math.max(maximum, current);
    });
    final codeWidth = math.max(520.0, maximumCharacters * 7.25 + 28);
    return Stack(
      key: _canvasKey,
      children: [
        Positioned.fill(
          bottom: 14,
          child: SelectionArea(
            child: CustomScrollView(
              key: ValueKey('code-review-canvas-${widget.source.name}'),
              controller: _verticalController,
              slivers: [
                for (final file in files)
                  SliverMainAxisGroup(
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _ReviewFileHeaderDelegate(
                          key: _headerKeys.putIfAbsent(
                            file.path,
                            GlobalKey.new,
                          ),
                          file: file,
                        ),
                      ),
                      SliverList.builder(
                        itemCount: parsed[file.path]!.length,
                        itemBuilder: (context, index) => _ReviewDiffRow(
                          key: ValueKey('review-row-${file.path}-$index'),
                          row: parsed[file.path]![index],
                          horizontalController: _horizontalController,
                          contentWidth: codeWidth,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 18)),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 88,
          right: 0,
          bottom: 0,
          height: 14,
          child: Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: codeWidth, height: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigation(
    BuildContext context,
    YeknomPalette palette,
    List<_ReviewFile> files,
  ) {
    final rows = _treeRows(files);
    return ColoredBox(
      color: palette.module,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            child: SizedBox(
              height: 30,
              child: TextField(
                key: const Key('code-review-file-filter'),
                controller: _search,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '筛选文件…',
                  prefixIcon: Icon(Icons.search, size: 16),
                  contentPadding: EdgeInsets.symmetric(vertical: 7),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() {
                  _queries[widget.source] = value;
                }),
              ),
            ),
          ),
          Divider(height: 1, color: palette.border),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('没有匹配的文件'))
                : ListView.builder(
                    key: const Key('code-review-file-tree'),
                    controller: _navigationController,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    itemExtent: _navigationRowExtent,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row.file case final file?) {
                        return _ReviewNavigationFileRow(
                          key: _navigationKeys.putIfAbsent(
                            file.path,
                            GlobalKey.new,
                          ),
                          file: file,
                          depth: row.depth,
                          selected: _selectedPaths[widget.source] == file.path,
                          writesEnabled:
                              widget.source == CodeReviewSource.gitWorkspace &&
                              !widget.controller.gitOperationRunning,
                          processing: _gitOperationPath == file.path,
                          onTap: () => _jumpToFile(file.path),
                          onStage:
                              file.gitChange != null &&
                                  !file.gitChange!.isStaged
                              ? () => _stage(file)
                              : null,
                          onRevert: file.gitChange == null
                              ? null
                              : () => _revert(file),
                        );
                      }
                      final directory = row.directory!;
                      final collapsed = _collapsedDirectories.contains(
                        directory.fullPath,
                      );
                      return InkWell(
                        onTap: () => setState(() {
                          if (!collapsed) {
                            _collapsedDirectories.add(directory.fullPath);
                          } else {
                            _collapsedDirectories.remove(directory.fullPath);
                          }
                        }),
                        child: SizedBox(
                          height: _navigationRowExtent,
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 8 + row.depth * 14,
                              right: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  collapsed
                                      ? Icons.chevron_right
                                      : Icons.expand_more,
                                  size: 15,
                                  color: palette.muted,
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.folder_outlined,
                                  size: 15,
                                  color: palette.muted,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    directory.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<_ReviewTreeRow> _treeRows(List<_ReviewFile> files) {
    final root = _ReviewDirectory('', '');
    for (final file in files) {
      final parts = file.path
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      var directory = root;
      for (var index = 0; index < parts.length - 1; index++) {
        final fullPath = parts.take(index + 1).join('/');
        directory = directory.children.putIfAbsent(
          parts[index],
          () => _ReviewDirectory(parts[index], fullPath),
        );
      }
      directory.files.add(file);
    }
    final rows = <_ReviewTreeRow>[];
    void append(_ReviewDirectory directory, int depth) {
      final children = directory.children.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final child in children) {
        rows.add(_ReviewTreeRow.directory(child, depth));
        if (!_collapsedDirectories.contains(child.fullPath)) {
          append(child, depth + 1);
        }
      }
      final directoryFiles = [...directory.files]
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in directoryFiles) {
        rows.add(_ReviewTreeRow.file(file, depth));
      }
    }

    append(root, 0);
    return rows;
  }
}

class _ReviewMessage extends StatelessWidget {
  const _ReviewMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: palette.muted),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewFileHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ReviewFileHeaderDelegate({required this.key, required this.file});

  final GlobalKey key;
  final _ReviewFile file;

  @override
  double get minExtent => 36;

  @override
  double get maxExtent => 36;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final palette = YeknomPalette.of(context);
    final stats = _reviewStats(file.diff);
    return Container(
      key: key,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: overlapsContent ? palette.raised : palette.module,
        border: Border(
          top: BorderSide(color: palette.border),
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: Row(
        children: [
          Icon(_reviewFileIcon(file.kind), size: 16, color: palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: file.path,
              child: Text(
                file.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (file.truncated)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 15,
                color: palette.warning,
              ),
            ),
          Text(
            file.diff.trim().isEmpty ? '+?' : '+${stats.additions}',
            style: TextStyle(color: palette.ack, fontSize: 11),
          ),
          const SizedBox(width: 6),
          Text(
            file.diff.trim().isEmpty ? '-?' : '-${stats.deletions}',
            style: TextStyle(color: palette.fault, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ReviewFileHeaderDelegate oldDelegate) =>
      oldDelegate.file != file || oldDelegate.key != key;
}

class _ReviewDiffRow extends StatelessWidget {
  const _ReviewDiffRow({
    required this.row,
    required this.horizontalController,
    required this.contentWidth,
    super.key,
  });

  final _ReviewRow row;
  final ScrollController horizontalController;
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final background = switch (row.kind) {
      _ReviewRowKind.addition => palette.ack.withValues(alpha: 0.10),
      _ReviewRowKind.deletion => palette.fault.withValues(alpha: 0.10),
      _ReviewRowKind.hunk => palette.active.withValues(alpha: 0.07),
      _ReviewRowKind.collapsed => palette.raised,
      _ => Colors.transparent,
    };
    final color = switch (row.kind) {
      _ReviewRowKind.addition => palette.ack,
      _ReviewRowKind.deletion => palette.fault,
      _ReviewRowKind.hunk => palette.active,
      _ReviewRowKind.metadata || _ReviewRowKind.noNewline => palette.muted,
      _ReviewRowKind.error => palette.fault,
      _ => palette.trace,
    };
    return Container(
      height: row.kind == _ReviewRowKind.collapsed ? 28 : 20,
      color: background,
      child: Row(
        children: [
          _ReviewLineNumber(value: row.oldLine),
          _ReviewLineNumber(value: row.newLine),
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: horizontalController,
                builder: (context, child) {
                  final offset = horizontalController.hasClients
                      ? horizontalController.offset
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(-offset, 0),
                    child: child,
                  );
                },
                child: SizedBox(
                  width: contentWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        row.text,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: color,
                          fontFamily: 'monospace',
                          fontSize: row.kind == _ReviewRowKind.collapsed
                              ? 11
                              : 12,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewLineNumber extends StatelessWidget {
  const _ReviewLineNumber({required this.value});

  final int? value;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      width: 44,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 7),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Text(
        value?.toString() ?? '',
        style: TextStyle(
          color: palette.muted,
          fontFamily: 'monospace',
          fontSize: 10,
        ),
      ),
    );
  }
}

class _ReviewNavigationFileRow extends StatefulWidget {
  const _ReviewNavigationFileRow({
    required this.file,
    required this.depth,
    required this.selected,
    required this.writesEnabled,
    required this.processing,
    required this.onTap,
    required this.onStage,
    required this.onRevert,
    super.key,
  });

  final _ReviewFile file;
  final int depth;
  final bool selected;
  final bool writesEnabled;
  final bool processing;
  final VoidCallback onTap;
  final Future<void> Function()? onStage;
  final Future<void> Function()? onRevert;

  @override
  State<_ReviewNavigationFileRow> createState() =>
      _ReviewNavigationFileRowState();
}

class _ReviewNavigationFileRowState extends State<_ReviewNavigationFileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final stats = _reviewStats(widget.file.diff);
    final showActions =
        _hovering && (widget.onStage != null || widget.onRevert != null);
    final name = widget.file.path.split('/').last;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        key: ValueKey('code-review-file-${widget.file.path}'),
        color: widget.selected ? palette.selected : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: SizedBox(
            height: 30,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 12 + widget.depth * 14,
                      right: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _reviewFileIcon(widget.file.kind),
                          size: 15,
                          color: widget.selected
                              ? palette.active
                              : palette.muted,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Tooltip(
                            message: widget.file.path,
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 58,
                          child: widget.processing
                              ? Center(
                                  child: SizedBox(
                                    key: const Key(
                                      'code-review-file-operation',
                                    ),
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.4,
                                      color: palette.active,
                                    ),
                                  ),
                                )
                              : showActions
                              ? const SizedBox.shrink()
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      widget.file.diff.trim().isEmpty
                                          ? '+?'
                                          : '+${stats.additions}',
                                      style: TextStyle(
                                        color: palette.ack,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.file.diff.trim().isEmpty
                                          ? '-?'
                                          : '-${stats.deletions}',
                                      style: TextStyle(
                                        color: palette.fault,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showActions && !widget.processing)
                  Positioned(
                    right: 7,
                    top: 1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onStage != null)
                          IconButton(
                            tooltip: '暂存文件',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 26,
                              height: 28,
                            ),
                            onPressed: widget.writesEnabled
                                ? widget.onStage
                                : null,
                            icon: const Icon(Icons.add_box_outlined, size: 15),
                          ),
                        if (widget.onRevert != null)
                          IconButton(
                            tooltip: '还原文件改动',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 26,
                              height: 28,
                            ),
                            onPressed: widget.writesEnabled
                                ? widget.onRevert
                                : null,
                            icon: const Icon(Icons.restore_outlined, size: 15),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class _ReviewFile {
  const _ReviewFile({
    required this.path,
    required this.kind,
    required this.diff,
    this.truncated = false,
    this.error,
    this.gitChange,
  });

  final String path;
  final String kind;
  final String diff;
  final bool truncated;
  final String? error;
  final GitProjectChange? gitChange;

  @override
  bool operator ==(Object other) =>
      other is _ReviewFile &&
      path == other.path &&
      kind == other.kind &&
      diff == other.diff &&
      truncated == other.truncated &&
      error == other.error;

  @override
  int get hashCode => Object.hash(path, kind, diff, truncated, error);
}

enum _ReviewRowKind {
  context,
  addition,
  deletion,
  hunk,
  collapsed,
  metadata,
  noNewline,
  error,
}

class _ReviewRow {
  const _ReviewRow(this.kind, this.text, {this.oldLine, this.newLine});

  final _ReviewRowKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;
}

final RegExp _hunkHeaderPattern = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$',
);

List<_ReviewRow> _parseReviewRows(_ReviewFile file) {
  if (file.error case final error?) {
    return [_ReviewRow(_ReviewRowKind.error, '无法读取 Diff：$error')];
  }
  if (file.diff.trim().isEmpty) {
    return const [_ReviewRow(_ReviewRowKind.metadata, '没有可显示的 Diff。')];
  }
  final rows = <_ReviewRow>[];
  var oldLine = 0;
  var newLine = 0;
  var previousOldEnd = 0;
  var previousNewEnd = 0;
  var sawHunk = false;
  for (final line in file.diff.split('\n')) {
    if (line.startsWith('diff --git ')) {
      oldLine = 0;
      newLine = 0;
      previousOldEnd = 0;
      previousNewEnd = 0;
      sawHunk = false;
      rows.add(_ReviewRow(_ReviewRowKind.metadata, line));
      continue;
    }
    final match = _hunkHeaderPattern.firstMatch(line);
    if (match != null) {
      final oldStart = int.parse(match.group(1)!);
      final newStart = int.parse(match.group(3)!);
      final oldGap = math.max(0, oldStart - previousOldEnd - 1);
      final newGap = math.max(0, newStart - previousNewEnd - 1);
      final gap = math.max(oldGap, newGap);
      if (gap > 0) {
        rows.add(_ReviewRow(_ReviewRowKind.collapsed, '未修改 $gap 行'));
      }
      rows.add(_ReviewRow(_ReviewRowKind.hunk, line));
      oldLine = oldStart;
      newLine = newStart;
      sawHunk = true;
      continue;
    }
    if (!sawHunk) {
      if (line.startsWith('index ') ||
          line.startsWith('--- ') ||
          line.startsWith('+++ ') ||
          line.startsWith('new file mode ') ||
          line.startsWith('deleted file mode ') ||
          line.startsWith('similarity index ') ||
          line.startsWith('rename from ') ||
          line.startsWith('rename to ') ||
          line.startsWith('Binary files ') ||
          line == 'GIT binary patch') {
        rows.add(_ReviewRow(_ReviewRowKind.metadata, line));
      }
      continue;
    }
    if (line.startsWith('\\ No newline at end of file')) {
      rows.add(_ReviewRow(_ReviewRowKind.noNewline, line));
      continue;
    }
    if (line.startsWith('+') && !line.startsWith('+++')) {
      rows.add(_ReviewRow(_ReviewRowKind.addition, line, newLine: newLine));
      newLine++;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      rows.add(_ReviewRow(_ReviewRowKind.deletion, line, oldLine: oldLine));
      oldLine++;
    } else {
      rows.add(
        _ReviewRow(
          _ReviewRowKind.context,
          line,
          oldLine: oldLine,
          newLine: newLine,
        ),
      );
      oldLine++;
      newLine++;
    }
    previousOldEnd = math.max(previousOldEnd, oldLine - 1);
    previousNewEnd = math.max(previousNewEnd, newLine - 1);
  }
  if (file.truncated) {
    rows.add(
      const _ReviewRow(_ReviewRowKind.metadata, '… Diff 已截断，当前只显示已加载内容。'),
    );
  }
  return rows.isEmpty
      ? const [_ReviewRow(_ReviewRowKind.metadata, '没有可显示的 Diff。')]
      : rows;
}

class _ReviewStats {
  const _ReviewStats({this.additions = 0, this.deletions = 0});

  final int additions;
  final int deletions;

  _ReviewStats operator +(_ReviewStats other) => _ReviewStats(
    additions: additions + other.additions,
    deletions: deletions + other.deletions,
  );
}

_ReviewStats _reviewStats(String diff) {
  var additions = 0;
  var deletions = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      additions++;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      deletions++;
    }
  }
  return _ReviewStats(additions: additions, deletions: deletions);
}

IconData _reviewFileIcon(String kind) {
  final normalized = kind.toLowerCase();
  if (normalized.contains('add') || normalized.contains('新增')) {
    return Icons.note_add_outlined;
  }
  if (normalized.contains('delete') || normalized.contains('删除')) {
    return Icons.delete_outline;
  }
  if (normalized.contains('rename') || normalized.contains('重命名')) {
    return Icons.drive_file_rename_outline;
  }
  if (normalized.contains('copy') || normalized.contains('复制')) {
    return Icons.file_copy_outlined;
  }
  if (normalized.contains('binary')) return Icons.data_object_outlined;
  return Icons.description_outlined;
}

class _ReviewDirectory {
  _ReviewDirectory(this.name, this.fullPath);

  final String name;
  final String fullPath;
  final Map<String, _ReviewDirectory> children = {};
  final List<_ReviewFile> files = [];
}

class _ReviewTreeRow {
  const _ReviewTreeRow.directory(this.directory, this.depth) : file = null;
  const _ReviewTreeRow.file(this.file, this.depth) : directory = null;

  final _ReviewDirectory? directory;
  final _ReviewFile? file;
  final int depth;
}
