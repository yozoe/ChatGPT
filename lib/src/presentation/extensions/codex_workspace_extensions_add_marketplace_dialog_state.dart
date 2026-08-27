// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_add_marketplace_dialog.dart';

class AddMarketplaceDialogState extends State<AddMarketplaceDialog> {
  final TextEditingController _source = TextEditingController();

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _chooseDirectory() async {
    final path = await getDirectoryPath(confirmButtonText: '选择插件市场');
    if (!mounted || path == null || path.trim().isEmpty) return;
    _source.text = path;
    _source.selection = TextSelection.collapsed(offset: path.length);
    setState(() {});
  }

  void _submit() {
    final value = _source.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final canSubmit = _source.text.trim().isNotEmpty;
    return AlertDialog(
      key: const Key('add-marketplace-dialog'),
      titlePadding: const EdgeInsets.fromLTRB(28, 25, 14, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              '添加插件市场',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '从 GitHub 仓库、Git URL 或本地文件夹添加。',
              style: TextStyle(color: palette.muted),
            ),
            const SizedBox(height: 24),
            const Text('来源', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('marketplace-source-field'),
              controller: _source,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'openai/plugins 或 git@github.com:org/repo.git',
                prefixIcon: const Icon(Icons.storefront_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 11),
            Text(
              '也可选择包含 marketplace 的本地文件夹。Git 引用由 Codex CLI 按市场默认设置解析。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      actions: [
        TextButton.icon(
          onPressed: _chooseDirectory,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('选择本地目录'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: const Text('添加市场'),
        ),
      ],
    );
  }
}
