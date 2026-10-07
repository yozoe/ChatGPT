import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_controller_builder.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_account_dialog.dart';

class CodexWorkspaceAccountDialogState
    extends State<CodexWorkspaceAccountDialog> {
  final TextEditingController apiKey = TextEditingController();

  @override
  void dispose() {
    apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ControllerBuilder(
      overrideController: widget.overrideController,
      builder: (context, controller) => AlertDialog(
        title: const Text('账户与登录'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前状态：${controller.authLabel}'),
              if (controller.accountEmail case final email?) ...[
                const SizedBox(height: 4),
                Text(email),
              ],
              const SizedBox(height: 16),
              if (!controller.canStopRuntime)
                const Text('请选择主目录；应用会自动连接本地运行时。')
              else ...[
                FilledButton.icon(
                  onPressed: controller.loginInProgress
                      ? null
                      : controller.startChatgptLogin,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('使用 ChatGPT 登录'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKey,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'OpenAI API Key',
                    hintText: 'sk-…',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) async {
                    await controller.loginWithApiKey(value);
                    apiKey.clear();
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '密钥不会被此应用写入项目或日志；它会交给本地 Codex 运行时处理。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: controller.loginInProgress
                      ? null
                      : () async {
                          await controller.loginWithApiKey(apiKey.text);
                          apiKey.clear();
                        },
                  child: const Text('使用 API Key 登录'),
                ),
                if (controller.loginUrl case final authUrl?) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    authUrl,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final opened = await launchUrl(
                        Uri.parse(authUrl),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法打开浏览器。')),
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('在浏览器中打开登录页'),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
