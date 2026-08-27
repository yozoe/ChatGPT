// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_editable_task_title.dart';

class EditableTaskTitleState extends State<EditableTaskTitle> {
  final TextEditingController _editor = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _editingThreadId;

  @override
  void dispose() {
    _editor.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _beginEditing(CodexThread thread) {
    setState(() {
      _editingThreadId = thread.id;
      _editor.text = thread.title;
      _editor.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editor.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _cancelEditing() {
    if (_editingThreadId == null) return;
    setState(() => _editingThreadId = null);
  }

  Future<void> _save(CodexThread thread) async {
    final nextName = _editor.text.trim();
    _cancelEditing();
    if (nextName.isEmpty || nextName == thread.title) return;
    await widget.controller.renameThread(thread, nextName);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final thread = activeThreadFor(widget.controller);
    final editing = thread != null && _editingThreadId == thread.id;
    final title = thread?.title ?? '新建任务';
    if (editing) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancelEditing,
        },
        child: TextField(
          key: const Key('workbench-task-title-editor'),
          controller: _editor,
          focusNode: _focusNode,
          maxLength: 120,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(thread),
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: palette.controlBorder),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: thread == null ? '发送第一条消息后可命名任务' : '点击重命名任务',
      child: Semantics(
        button: thread != null,
        label: '当前任务：$title',
        child: InkWell(
          key: const Key('workbench-task-title'),
          onTap: thread == null ? null : () => _beginEditing(thread),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (thread != null) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.edit_outlined, size: 16, color: palette.muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
