import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class CodexWorkspaceDeleteThreadDialog extends StatelessWidget {
  const CodexWorkspaceDeleteThreadDialog({super.key, required this.thread});

  final CodexThread thread;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('永久删除任务？'),
      content: Text(
        '“${thread.title}”及其派生任务会从 Codex 中永久删除，无法恢复。本应用的对应本地缓存引用也会移除。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('永久删除'),
        ),
      ],
    );
  }
}
