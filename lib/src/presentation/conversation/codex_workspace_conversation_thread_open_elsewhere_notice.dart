// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class ThreadOpenElsewhereNotice extends StatelessWidget {
  const ThreadOpenElsewhereNotice({
    required this.retrying,
    required this.onRetry,
    this.feedback,
  });

  final bool retrying;
  final Future<void> Function() onRetry;
  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      container: true,
      label: '已在另一个应用中打开。请先在那边关闭会话，然后重试此操作。',
      child: Container(
        key: const Key('thread-open-elsewhere-notice'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: palette.field,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: palette.trace),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已在另一个应用中打开',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.trace,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    feedback ?? '请先在那边关闭会话，然后重试此操作。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.muted),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 28, color: palette.border),
            TextButton(
              key: const Key('thread-open-elsewhere-retry'),
              onPressed: retrying ? null : onRetry,
              child: Text(retrying ? '重试中' : '重试'),
            ),
          ],
        ),
      ),
    );
  }
}
