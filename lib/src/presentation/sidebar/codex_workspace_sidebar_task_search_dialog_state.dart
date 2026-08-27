// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_result.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_dialog.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_section_label.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_result_tile.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_task_search_action_tile.dart';

class TaskSearchDialogState extends State<TaskSearchDialog> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  static const _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  List<TaskSearchResult> get _filteredResults {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.results;
    return widget.results
        .where(
          (result) =>
              result.thread.title.toLowerCase().contains(query) ||
              result.thread.preview.toLowerCase().contains(query) ||
              result.workspaceName.toLowerCase().contains(query) ||
              result.providerLabel.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _closeThen(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  void _openResult(TaskSearchResult result) {
    if (!widget.canOpenTask(result)) return;
    Navigator.of(context).pop();
    unawaited(widget.onOpenTask(result));
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final results = _filteredResults;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            _closeThen(widget.onNewTask),
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
            _closeThen(widget.onOpenWorkspace),
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () {
          if (!widget.canSearchFiles) return;
          Navigator.of(context).pop();
          unawaited(widget.onSearchFiles());
        },
        for (var index = 0; index < 9; index++)
          SingleActivator(_digitKeys[index], meta: true): () {
            if (index < results.length && widget.canOpenTask(results[index])) {
              _openResult(results[index]);
            }
          },
      },
      child: Dialog(
        key: const Key('task-search-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Material(
            color: palette.module,
            elevation: 24,
            shadowColor: Colors.black.withValues(alpha: 0.45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
              side: BorderSide(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('task-search-dialog-field'),
                    controller: _search,
                    focusNode: _focusNode,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.45,
                    ),
                    decoration: InputDecoration(
                      hintText: '搜索聊天',
                      hintStyle: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: palette.muted,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.45,
                          ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const TaskSearchSectionLabel(label: '聊天'),
                  const SizedBox(height: 7),
                  Flexible(
                    child: results.isEmpty
                        ? Center(
                            child: Text(
                              '没有匹配的聊天',
                              style: TextStyle(color: palette.muted),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: results.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 2),
                            itemBuilder: (context, index) => TaskSearchResultTile(
                              key: ValueKey(
                                'task-search-result-${results[index].thread.id}',
                              ),
                              result: results[index],
                              shortcut: index < 9 ? '⌘${index + 1}' : null,
                              enabled: widget.canOpenTask(results[index]),
                              onTap: () => _openResult(results[index]),
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  const TaskSearchSectionLabel(label: '快捷操作'),
                  const SizedBox(height: 7),
                  TaskSearchActionTile(
                    icon: Icons.edit_outlined,
                    label: '新聊天',
                    shortcut: '⌘N',
                    enabled: widget.canCreateTask,
                    onTap: () => _closeThen(widget.onNewTask),
                  ),
                  TaskSearchActionTile(
                    icon: Icons.folder_open_outlined,
                    label: '打开文件夹',
                    shortcut: '⌘O',
                    onTap: () => _closeThen(widget.onOpenWorkspace),
                  ),
                  TaskSearchActionTile(
                    icon: Icons.search_outlined,
                    label: '搜索文件',
                    shortcut: '⌘P',
                    enabled: widget.canSearchFiles,
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(widget.onSearchFiles());
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
