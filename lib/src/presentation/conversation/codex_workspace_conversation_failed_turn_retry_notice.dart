// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class FailedTurnRetryNotice extends StatelessWidget {
  const FailedTurnRetryNotice({
    super.key,
    required this.error,
    required this.retrying,
    required this.enabled,
    required this.onRetry,
    this.secondsRemaining,
    this.automaticRetrying = false,
    this.onCancelAutomaticRetry,
  });

  final String error;
  final bool retrying;
  final bool enabled;
  final Future<bool> Function() onRetry;
  final int? secondsRemaining;
  final bool automaticRetrying;
  final VoidCallback? onCancelAutomaticRetry;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      key: const Key('failed-turn-retry-notice'),
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
          const SizedBox(width: 10),
          if (secondsRemaining != null && !automaticRetrying)
            TextButton(
              key: const Key('failed-turn-auto-retry-countdown'),
              onPressed: onCancelAutomaticRetry,
              style: TextButton.styleFrom(
                foregroundColor: palette.fault,
                backgroundColor: palette.fault.withValues(alpha: 0.12),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                shape: const StadiumBorder(),
              ),
              child: Text('$secondsRemaining秒后重试'),
            )
          else
            TextButton.icon(
              key: const Key('failed-turn-retry-button'),
              onPressed: retrying || !enabled
                  ? null
                  : () => unawaited(onRetry()),
              icon: retrying
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 17),
              label: Text(retrying ? '重试中' : '重试'),
              style: TextButton.styleFrom(
                foregroundColor: palette.fault,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              ),
            ),
        ],
      ),
    );
  }
}
