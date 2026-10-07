import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_controller_builder.dart';

class CodexWorkspaceRuntimeDialog extends StatelessWidget {
  const CodexWorkspaceRuntimeDialog({
    super.key,
    this.overrideController,
    required this.onCopyDiagnostics,
    required this.onExportDiagnostics,
  });

  final CodexController? overrideController;
  final Future<void> Function() onCopyDiagnostics;
  final Future<void> Function() onExportDiagnostics;

  @override
  Widget build(BuildContext context) {
    return ControllerBuilder(
      overrideController: overrideController,
      builder: (context, controller) {
        final probe = controller.runtimeProbe;
        return AlertDialog(
          title: const Text('Codex CLI 运行时'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.runtimeChecking)
                    const LinearProgressIndicator()
                  else if (probe?.isAvailable == true) ...[
                    const Text('已检测到可用的 Codex CLI。'),
                    const SizedBox(height: 8),
                    SelectableText(probe!.executablePath ?? ''),
                    if (probe.version?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        probe.version!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ] else ...[
                    Text(controller.runtimeError ?? '尚未检测到 Codex CLI。'),
                    const SizedBox(height: 12),
                    const Text('可在终端执行以下官方安装命令：'),
                    const SizedBox(height: 6),
                    const SelectableText(
                      'curl -fsSL https://chatgpt.com/codex/install.sh | sh',
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '选择的路径仅保存为本应用设置；启动时会再次验证，不依赖 Finder 的 PATH。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: controller.runtimeDiagnostics,
                    builder: (context, _) {
                      final logs = controller.runtimeLogs;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '最近运行时日志（${logs.length}/200）',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: logs.isEmpty
                                    ? null
                                    : controller.clearRuntimeLogs,
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            key: const Key('runtime-diagnostics-log'),
                            constraints: const BoxConstraints(maxHeight: 180),
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                logs.isEmpty
                                    ? '本次应用运行中尚未记录 stderr 或协议日志。'
                                    : logs
                                          .map(
                                            (entry) => entry.toDiagnosticLine(),
                                          )
                                          .join('\n'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '日志只保留在内存中，最多 200 条；展示和复制前都会脱敏。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              key: const Key('copy-runtime-diagnostics-button'),
              onPressed: onCopyDiagnostics,
              icon: const Icon(Icons.content_copy_outlined, size: 18),
              label: const Text('复制诊断'),
            ),
            TextButton.icon(
              key: const Key('export-runtime-diagnostics-button'),
              onPressed: onExportDiagnostics,
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('导出诊断'),
            ),
            TextButton(
              onPressed:
                  controller.canConfigureRuntime && !controller.runtimeChecking
                  ? () async {
                      final file = await openFile(
                        confirmButtonText: '使用此 Codex CLI',
                      );
                      if (file != null) {
                        await controller.setRuntimeExecutable(file.path);
                      }
                    }
                  : null,
              child: const Text('选择可执行文件'),
            ),
            if (controller.canConfigureRuntime)
              TextButton(
                onPressed: controller.runtimeChecking
                    ? null
                    : controller.resetRuntimeExecutable,
                child: const Text('恢复自动检测'),
              ),
            TextButton(
              onPressed: controller.runtimeChecking
                  ? null
                  : controller.inspectRuntime,
              child: const Text('重新检测'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
