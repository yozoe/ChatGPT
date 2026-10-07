import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_controller_builder.dart';

class CodexConfigurationDialog extends StatelessWidget {
  const CodexConfigurationDialog({super.key, this.overrideController});

  final CodexController? overrideController;

  @override
  Widget build(BuildContext context) {
    return ControllerBuilder(
      overrideController: overrideController,
      builder: (context, controller) => AlertDialog(
        key: const Key('codex-configuration-dialog'),
        title: const Text('Codex 配置'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '模型、Provider、Base URL 和凭据由本地 Codex App Server 按配置优先级直接读取，本应用不再单独收集或保存这些字段。',
                ),
                const SizedBox(height: 16),
                Text('读取状态', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  controller.codexConfigurationStatusLabel,
                  key: const Key('codex-configuration-status'),
                ),
                if (controller.codexConfigurationError case final error?) ...[
                  const SizedBox(height: 4),
                  Text(
                    error,
                    key: const Key('codex-configuration-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text('当前模型', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(
                  controller.configuredModelLabel,
                  key: const Key('codex-configured-model'),
                ),
                const SizedBox(height: 4),
                Text(
                  '来源：${controller.configuredModelSourceLabel}',
                  key: const Key('codex-configured-model-source'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  'Provider',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  controller.providerLabel,
                  key: const Key('codex-configured-provider'),
                ),
                const SizedBox(height: 4),
                Text(
                  '来源：${controller.configuredProviderSourceLabel}',
                  key: const Key('codex-configured-provider-source'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  '当前 profile',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  controller.agentDefaultSettings.profile ?? '默认 profile',
                  key: const Key('codex-configured-profile'),
                ),
                const SizedBox(height: 4),
                Text(
                  '来源：${controller.agentDefaultSettings.profileSource ?? '由 Codex 配置管理'}',
                  key: const Key('codex-configured-profile-source'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text('用户配置文件', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(
                  controller.codexUserConfigPath,
                  key: const Key('codex-configuration-path'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('codex-open-config-file'),
                    onPressed: () async {
                      final opened = await launchUrl(
                        Uri.file(controller.codexUserConfigPath),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法打开 config.toml。')),
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('打开 config.toml'),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '“已读取”表示模型和 Provider 已由 Codex 运行时解析；凭据、网络和 Base URL 是否可用，仍需成功创建一次任务才能确认。',
                  key: const Key('codex-configuration-verification-note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '输入框右下角的模型和推理强度选择只影响后续新建任务，不会改写 Codex 配置，也不会覆盖历史任务原有模型。',
                  key: const Key('codex-model-selection-scope-note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
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
