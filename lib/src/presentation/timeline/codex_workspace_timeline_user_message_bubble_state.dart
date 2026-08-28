// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_user_message_bubble.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_timeline_image.dart';
import 'package:flutter/services.dart';

class UserMessageBubbleState extends State<UserMessageBubble> {
  var _hovering = false;
  var _editing = false;
  var _submittingEdit = false;
  late TextEditingController _editor;

  @override
  void initState() {
    super.initState();
    _editor = TextEditingController(text: widget.entry.detail);
    _editor.addListener(_handleEditorChanged);
  }

  void _handleEditorChanged() {
    if (mounted && _editing) setState(() {});
  }

  @override
  void didUpdateWidget(covariant UserMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _editing = false;
      _submittingEdit = false;
      _editor
        ..text = widget.entry.detail
        ..selection = TextSelection.collapsed(
          offset: widget.entry.detail.length,
        );
    }
  }

  @override
  void dispose() {
    _editor.removeListener(_handleEditorChanged);
    _editor.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _hovering = false;
      _editor
        ..text = widget.entry.detail
        ..selection = TextSelection.collapsed(
          offset: widget.entry.detail.length,
        );
    });
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
      _submittingEdit = false;
      _editor.text = widget.entry.detail;
    });
  }

  Future<void> _submitEdit() async {
    final submit = widget.onSubmitEdit;
    final text = _editor.text.trim();
    if (submit == null || text.isEmpty || _submittingEdit) return;
    setState(() => _submittingEdit = true);
    final sent = await submit(widget.entry, text);
    if (!mounted) return;
    setState(() {
      _submittingEdit = false;
      if (sent) _editing = false;
    });
  }

  Widget _messageBody(YeknomPalette palette) => Container(
    key: const Key('timeline-user-message'),
    padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
    decoration: BoxDecoration(
      color: palette.raised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: palette.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionArea(child: Text(widget.entry.detail)),
        if (widget.entry.imagePaths.isNotEmpty) ...[
          const SizedBox(height: 9),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final path in widget.entry.imagePaths)
                  TimelineImage(path: path),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _actionButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    required YeknomPalette palette,
  }) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: palette.muted),
        ),
      ),
    ),
  );

  Widget _editorBody(YeknomPalette palette) => Container(
    key: const Key('timeline-user-message-editor'),
    padding: const EdgeInsets.fromLTRB(13, 10, 10, 12),
    decoration: BoxDecoration(
      color: palette.raised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: palette.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('timeline-user-message-editor-field'),
          controller: _editor,
          autofocus: true,
          enabled: !_submittingEdit,
          minLines: 3,
          maxLines: 8,
          style: TextStyle(color: palette.trace, fontSize: 13, height: 1.4),
          decoration: const InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const Key('timeline-user-message-edit-cancel'),
                onPressed: _submittingEdit ? null : _cancelEditing,
                style: TextButton.styleFrom(
                  foregroundColor: palette.trace,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  minimumSize: Size.zero,
                  side: BorderSide(color: palette.controlBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                child: const Text('取消'),
              ),
              const SizedBox(width: 7),
              FilledButton(
                key: const Key('timeline-user-message-edit-send'),
                onPressed: _submittingEdit || _editor.text.trim().isEmpty
                    ? null
                    : () => unawaited(_submitEdit()),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.trace,
                  foregroundColor: palette.module,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                child: _submittingEdit
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: MouseRegion(
        key: const Key('timeline-user-message-hover-region'),
        onEnter: _editing ? null : (_) => setState(() => _hovering = true),
        onExit: _editing ? null : (_) => setState(() => _hovering = false),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _editing
              ? _editorBody(palette)
              : Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 23),
                      child: _messageBody(palette),
                    ),
                    if (_hovering)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              messageTimeLabel(widget.entry.createdAt),
                              key: const Key('timeline-user-message-time'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: palette.muted,
                                    fontSize: 12,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(width: 7),
                            _actionButton(
                              key: ValueKey(
                                'timeline-user-message-copy-${widget.entry.id}',
                              ),
                              tooltip: '复制消息',
                              icon: Icons.content_copy_outlined,
                              onTap: () => unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: widget.entry.detail),
                                ),
                              ),
                              palette: palette,
                            ),
                            if (widget.onSubmitEdit != null)
                              _actionButton(
                                key: ValueKey(
                                  'timeline-user-message-edit-${widget.entry.id}',
                                ),
                                tooltip: '修改消息',
                                icon: Icons.edit_outlined,
                                onTap: _startEditing,
                                palette: palette,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
