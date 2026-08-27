// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class FailedTurnRetryNotice extends StatelessWidget {
  const FailedTurnRetryNotice({
    required this.error,
    required this.retrying,
    required this.enabled,
    required this.onRetry,
  });

  final String error;
  final bool retrying;
  final bool enabled;
  final Future<bool> Function() onRetry;

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
          TextButton.icon(
            key: const Key('failed-turn-retry-button'),
            onPressed: retrying || !enabled ? null : () => unawaited(onRetry()),
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
