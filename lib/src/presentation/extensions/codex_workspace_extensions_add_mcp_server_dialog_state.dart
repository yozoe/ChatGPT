// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_add_mcp_server_dialog.dart';

class AddMcpServerDialogState extends State<AddMcpServerDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting ||
        widget.controller.pluginSaving ||
        _name.text.trim().isEmpty ||
        _url.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final succeeded = await widget.controller.addMcpServer(
      name: _name.text,
      url: _url.text,
    );
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop();
      return;
    }
    final error = widget.controller.pluginActionError ?? '添加 MCP 服务器失败。';
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('add-mcp-server-dialog'),
    title: const Text('添加 MCP 服务器'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('mcp-server-name-field'),
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '名称'),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('mcp-server-url-field'),
            controller: _url,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '服务器 URL',
              hintText: 'https://example.com/mcp',
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                key: const Key('add-mcp-server-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('submit-mcp-server-button'),
        onPressed:
            _submitting || _name.text.trim().isEmpty || _url.text.trim().isEmpty
            ? null
            : _submit,
        child: _submitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('添加'),
      ),
    ],
  );
}
