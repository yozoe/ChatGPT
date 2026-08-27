// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class ArchivedThreadTile extends StatelessWidget {
  const ArchivedThreadTile({
    required this.thread,
    required this.enabled,
    required this.restoring,
    required this.onRestore,
    required this.onDelete,
  });

  final CodexThread thread;
  final bool enabled;
  final bool restoring;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  /// 构建带恢复操作与进行状态的归档线程项。
  /// Builds an archived-thread item with restore action and progress state.
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: thread.status == null ? null : Text(thread.status!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: enabled ? onRestore : null,
            icon: restoring
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.unarchive_outlined, size: 18),
            label: Text(restoring ? '恢复中' : '恢复'),
          ),
          IconButton(
            tooltip: '永久删除任务',
            onPressed: enabled && !restoring ? onDelete : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
