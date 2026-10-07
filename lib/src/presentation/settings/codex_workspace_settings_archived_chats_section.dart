import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class SettingsArchivedChatsSection extends StatelessWidget {
  const SettingsArchivedChatsSection({
    super.key,
    required this.controller,
    required this.archiveSearch,
    required this.archiveTypeFilter,
    required this.archiveProjectFilter,
    required this.projectName,
    required this.buildMessage,
    required this.archiveDate,
    required this.onSearchChanged,
    required this.onTypeFilterChanged,
    required this.onProjectFilterChanged,
    required this.onDeleteThread,
    required this.onDeleteAllThreads,
  });

  final CodexController controller;
  final TextEditingController archiveSearch;
  final String archiveTypeFilter;
  final String archiveProjectFilter;
  final String projectName;
  final Widget Function({
    required Key key,
    required String title,
    required String detail,
  })
  buildMessage;
  final String Function(CodexThread thread) archiveDate;
  final VoidCallback onSearchChanged;
  final ValueChanged<String> onTypeFilterChanged;
  final ValueChanged<String> onProjectFilterChanged;
  final Future<void> Function(CodexThread thread) onDeleteThread;
  final Future<void> Function() onDeleteAllThreads;

  Widget _archivedThreadRow(BuildContext context, CodexThread thread) {
    final palette = YeknomPalette.of(context);
    final updating = controller.isUpdatingThread(thread.id);
    final restoring = controller.isUnarchivingThread(thread.id);
    final enabled = controller.status == RuntimeStatus.ready && !updating;
    final canDelete = enabled && !controller.hasRunningTasks;
    return Container(
      key: Key('settings-archived-thread-${thread.id}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  archiveDate(thread),
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (updating || restoring)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              key: Key('settings-archived-delete-${thread.id}'),
              tooltip: '永久删除',
              onPressed: canDelete ? () => onDeleteThread(thread) : null,
              icon: const Icon(Icons.delete_outline, size: 17),
            ),
            TextButton(
              key: Key('settings-archived-unarchive-${thread.id}'),
              onPressed: enabled
                  ? () => controller.unarchiveThread(thread)
                  : null,
              child: const Text('取消归档'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final query = archiveSearch.text.trim().toLowerCase();
        final threads = controller.archivedThreads
            .where((thread) {
              final matchesQuery =
                  query.isEmpty ||
                  '${thread.title} ${thread.preview}'.toLowerCase().contains(
                    query,
                  );
              final matchesProject = archiveProjectFilter == '当前项目';
              return matchesQuery && matchesProject;
            })
            .toList(growable: false);
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            return ListView(
              key: const Key('settings-archived-chats-page'),
              padding: EdgeInsets.fromLTRB(
                compact ? 24 : 72,
                46,
                compact ? 24 : 72,
                72,
              ),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                '已归档的聊天',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                            TextButton.icon(
                              key: const Key('settings-archived-delete-all'),
                              onPressed:
                                  controller.archivedThreads.isEmpty ||
                                      controller.status !=
                                          RuntimeStatus.ready ||
                                      controller.hasRunningTasks
                                  ? null
                                  : onDeleteAllThreads,
                              icon: const Icon(Icons.delete_outline, size: 15),
                              label: const Text('全部删除'),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 34),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: compact ? constraints.maxWidth : 330,
                              height: 40,
                              child: TextField(
                                key: const Key('settings-archived-search'),
                                controller: archiveSearch,
                                onChanged: (_) => onSearchChanged(),
                                decoration: const InputDecoration(
                                  hintText: '搜索已归档聊天',
                                  prefixIcon: Icon(Icons.search, size: 17),
                                  prefixIconConstraints: BoxConstraints(
                                    minWidth: 38,
                                    maxWidth: 38,
                                    minHeight: 40,
                                    maxHeight: 40,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              key: const Key('settings-archived-type-filter'),
                              initialValue: archiveTypeFilter,
                              onSelected: onTypeFilterChanged,
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: '全部聊天',
                                  child: Text('全部聊天'),
                                ),
                              ],
                              child: Chip(
                                avatar: const Icon(Icons.tune, size: 15),
                                label: Text(archiveTypeFilter),
                              ),
                            ),
                            PopupMenuButton<String>(
                              key: const Key(
                                'settings-archived-project-filter',
                              ),
                              initialValue: archiveProjectFilter,
                              onSelected: onProjectFilterChanged,
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: '当前项目',
                                  child: Text('当前项目'),
                                ),
                              ],
                              child: Chip(
                                avatar: const Icon(
                                  Icons.folder_outlined,
                                  size: 15,
                                ),
                                label: Text(archiveProjectFilter),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        if (controller.archivedThreadsLoading)
                          const Center(child: CircularProgressIndicator())
                        else if (controller.archivedThreadsError
                            case final error?)
                          buildMessage(
                            key: const Key('settings-archived-error-state'),
                            title: '无法读取已归档聊天',
                            detail: error,
                          )
                        else if (threads.isEmpty)
                          buildMessage(
                            key: const Key('settings-archived-empty-state'),
                            title: query.isEmpty ? '暂无已归档聊天' : '未找到匹配的聊天',
                            detail: query.isEmpty
                                ? '归档的聊天会显示在这里。'
                                : '请尝试其他搜索词。',
                          )
                        else
                          DecoratedBox(
                            key: const Key('settings-archived-list'),
                            decoration: BoxDecoration(
                              color: palette.raised,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: palette.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    14,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.folder_outlined,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(projectName)),
                                      Text(
                                        '${threads.length} 个聊天',
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.more_horiz, size: 17),
                                    ],
                                  ),
                                ),
                                for (final thread in threads)
                                  _archivedThreadRow(context, thread),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
