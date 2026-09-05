import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class UsageLimitNotice extends StatelessWidget {
  const UsageLimitNotice({
    super.key,
    required this.error,
    required this.retrying,
    required this.retryEnabled,
    required this.onRetry,
  });

  final String error;
  final bool retrying;
  final bool retryEnabled;
  final Future<bool> Function() onRetry;

  Future<void> _openUsage(BuildContext context) async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://chatgpt.com/codex/settings/usage'),
        mode: LaunchMode.externalApplication,
      );
      if (opened || !context.mounted) return;
    } catch (_) {
      if (!context.mounted) return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开用量面板。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      key: const Key('usage-limit-notice'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: palette.fault.withValues(alpha: 0.09),
        border: Border.all(color: palette.fault.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 15, color: palette.fault),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.fault),
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                key: const Key('usage-limit-open-button'),
                onPressed: () => unawaited(_openUsage(context)),
                child: const Text('查看用量'),
              ),
              TextButton.icon(
                key: const Key('usage-limit-retry-button'),
                onPressed: retrying || !retryEnabled
                    ? null
                    : () => unawaited(onRetry()),
                icon: retrying
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 17),
                label: Text(retrying ? '重试中' : '额度恢复后重试'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
