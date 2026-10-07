import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_archived_thread_tile.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_controller_builder.dart';

class CodexWorkspaceArchivedThreadsDialog extends StatelessWidget {
  const CodexWorkspaceArchivedThreadsDialog({
    super.key,
    this.overrideController,
    required this.onDelete,
  });

  final CodexController? overrideController;
  final Future<void> Function(CodexThread thread) onDelete;

  @override
  Widget build(BuildContext context) {
    return ControllerBuilder(
      overrideController: overrideController,
      builder: (context, controller) {
        return AlertDialog(
          title: const Text('已归档任务'),
          content: SizedBox(
            width: 480,
            height: 420,
            child: switch ((
              controller.archivedThreadsLoading,
              controller.archivedThreadsError,
              controller.archivedThreads,
            )) {
              (true, _, _) => const Center(child: CircularProgressIndicator()),
              (_, final String error, _) => Center(child: Text(error)),
              (_, _, final List<CodexThread> threads) when threads.isEmpty =>
                const Center(child: Text('暂无归档任务。')),
              (_, _, final List<CodexThread> threads) => ListView.separated(
                itemCount: threads.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final thread = threads[index];
                  return ArchivedThreadTile(
                    thread: thread,
                    enabled:
                        controller.status == RuntimeStatus.ready &&
                        !controller.isUnarchivingThread(thread.id) &&
                        !controller.isUpdatingThread(thread.id),
                    restoring: controller.isUnarchivingThread(thread.id),
                    onRestore: () => controller.unarchiveThread(thread),
                    onDelete: () => onDelete(thread),
                  );
                },
              ),
            },
          ),
          actions: [
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
