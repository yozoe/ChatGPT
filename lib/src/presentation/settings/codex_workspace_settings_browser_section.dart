import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class SettingsBrowserSection extends StatelessWidget {
  const SettingsBrowserSection({
    super.key,
    required this.controller,
    required this.onChooseDownloadDirectory,
  });

  final CodexController controller;
  final Future<void> Function() onChooseDownloadDirectory;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 46, 72, 0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '浏览器',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '浏览器由智能体在任务执行中按需调用。此页面仅用于配置能力与权限。',
              style: TextStyle(color: palette.muted),
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  Semantics(
                    container: true,
                    label: '允许智能体调用内置浏览器',
                    toggled: controller.browserEnabled,
                    onTap: () => unawaited(
                      controller.setBrowserEnabled(!controller.browserEnabled),
                    ),
                    child: ExcludeSemantics(
                      child: SwitchListTile(
                        key: const Key('settings-browser-enabled'),
                        secondary: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('允许智能体调用内置浏览器'),
                        subtitle: const Text(
                          '任务中收到受支持的 browser 请求时，会先请求批准；批准后打开浏览器工作区。computer-use 活动仅展示状态，不会自动导航。',
                        ),
                        value: controller.browserEnabled,
                        onChanged: (enabled) =>
                            unawaited(controller.setBrowserEnabled(enabled)),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('settings-browser-link-open-mode'),
                    leading: const Icon(Icons.open_in_browser_outlined),
                    title: const Text('网页链接打开位置'),
                    subtitle: const Text(
                      '用户点击回复中的 HTTP/HTTPS 链接时使用的浏览器。智能体请求始终单独请求批准。',
                    ),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<BrowserLinkOpenMode>(
                        value: controller.browserLinkOpenMode,
                        onChanged: (mode) {
                          if (mode != null) {
                            unawaited(controller.setBrowserLinkOpenMode(mode));
                          }
                        },
                        items: const [
                          DropdownMenuItem(
                            value: BrowserLinkOpenMode.system,
                            child: Text('系统浏览器'),
                          ),
                          DropdownMenuItem(
                            value: BrowserLinkOpenMode.inApp,
                            child: Text('内置浏览器'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Semantics(
                    container: true,
                    label: '每次下载前询问保存位置',
                    toggled: controller.browserAskBeforeDownload,
                    onTap: () => unawaited(
                      controller.setBrowserAskBeforeDownload(
                        !controller.browserAskBeforeDownload,
                      ),
                    ),
                    child: ExcludeSemantics(
                      child: SwitchListTile(
                        key: const Key('settings-browser-ask-before-download'),
                        secondary: const Icon(Icons.download_outlined),
                        title: const Text('每次下载前询问保存位置'),
                        subtitle: Text(
                          controller.browserDownloadDirectory == null
                              ? '未设置默认目录；关闭后需要先选择下载目录。'
                              : '关闭后自动保存到：${controller.browserDownloadDirectory}',
                        ),
                        value: controller.browserAskBeforeDownload,
                        onChanged: (ask) => unawaited(
                          controller.setBrowserAskBeforeDownload(ask),
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    key: const Key('settings-browser-download-directory'),
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('默认下载目录'),
                    subtitle: Text(
                      controller.browserDownloadDirectory ?? '每次下载时选择',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: onChooseDownloadDirectory,
                          child: const Text('选择'),
                        ),
                        if (controller.browserDownloadDirectory != null)
                          IconButton(
                            tooltip: '清除默认下载目录',
                            onPressed: () => unawaited(
                              controller.setBrowserDownloadDirectory(null),
                            ),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Semantics(
                    container: true,
                    label: '启动时恢复浏览器标签',
                    toggled: controller.browserRestoreTabs,
                    onTap: () => unawaited(
                      controller.setBrowserRestoreTabs(
                        !controller.browserRestoreTabs,
                      ),
                    ),
                    child: ExcludeSemantics(
                      child: SwitchListTile(
                        key: const Key('settings-browser-restore-tabs'),
                        secondary: const Icon(Icons.restore_page_outlined),
                        title: const Text('启动时恢复浏览器标签'),
                        subtitle: const Text(
                          '恢复保存的网页地址和标签标题，不恢复 Cookie、网站存储或登录状态。默认关闭。',
                        ),
                        value: controller.browserRestoreTabs,
                        onChanged: (restore) => unawaited(
                          controller.setBrowserRestoreTabs(restore),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '当前只接收 App Server 明确声明的 HTTP/HTTPS 导航请求；不会读取或复用 Chrome、Safari 的登录状态。',
              style: TextStyle(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
