// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class ArchivedThreadNotice extends StatelessWidget {
  const ArchivedThreadNotice({
    required this.restoring,
    required this.onRestore,
  });

  final bool restoring;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      container: true,
      label: '此任务已归档。取消归档后会重新出现在任务列表中。',
      child: Container(
        key: const Key('thread-archived-notice'),
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
            Icon(Icons.inventory_2_outlined, size: 16, color: palette.trace),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '此任务已归档',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.trace,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '取消归档后会重新出现在任务列表中。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.muted),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 28, color: palette.border),
            TextButton(
              key: const Key('thread-archived-unarchive'),
              onPressed: restoring ? null : onRestore,
              child: Text(restoring ? '取消归档中' : '取消归档'),
            ),
          ],
        ),
      ),
    );
  }
}
