import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class SettingsHelpActions {
  const SettingsHelpActions._();

  static Future<void> showShortcuts(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('settings-shortcuts-dialog'),
        title: const Text('键盘快捷键'),
        content: const SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.add_comment_outlined),
                title: Text('新对话'),
                trailing: Text('⌘ N'),
              ),
              ListTile(
                leading: Icon(Icons.search_outlined),
                title: Text('搜索聊天'),
                trailing: Text('⌘ K'),
              ),
              ListTile(
                leading: Icon(Icons.stop_circle_outlined),
                title: Text('停止当前任务'),
                trailing: Text('Esc'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  static void showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Codex Desk',
      applicationVersion: '1.0.0',
      applicationLegalese: '本地优先 · stdio JSON-RPC',
    );
  }
}
