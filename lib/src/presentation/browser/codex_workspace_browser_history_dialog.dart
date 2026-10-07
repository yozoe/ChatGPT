import 'package:chatgpt/src/domain/browser_history_entry.dart';
import 'package:chatgpt/src/services/browser_history_store.dart';
import 'package:flutter/material.dart';

/// Dialog for searching, opening, and removing application-local browser history.
class BrowserHistoryDialog extends StatelessWidget {
  const BrowserHistoryDialog({
    required this.entries,
    required this.store,
    required this.onOpen,
    super.key,
  });

  final List<BrowserHistoryEntry> entries;
  final BrowserHistoryStore store;
  final ValueChanged<Uri> onOpen;

  @override
  Widget build(BuildContext context) {
    var query = '';
    return StatefulBuilder(
      builder: (context, setDialogState) {
        final filtered = entries
            .where((entry) {
              final haystack = '${entry.title}\n${entry.url}'.toLowerCase();
              return haystack.contains(query.trim().toLowerCase());
            })
            .toList(growable: false);
        return AlertDialog(
          title: const Text('浏览历史'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                TextField(
                  key: const Key('browser-history-search'),
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索标题或网址',
                  ),
                  onChanged: (value) => setDialogState(() => query = value),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(entries.isEmpty ? '暂无浏览历史' : '没有匹配的历史记录'),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            return ListTile(
                              title: Text(entry.title),
                              subtitle: Text(entry.url),
                              trailing: IconButton(
                                tooltip: '删除此记录',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await store.remove(entry.url);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                final uri = Uri.tryParse(entry.url);
                                if (uri != null) onOpen(uri);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            if (entries.isNotEmpty)
              TextButton(
                key: const Key('browser-clear-history'),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (confirmContext) => AlertDialog(
                      title: const Text('清空浏览历史？'),
                      content: const Text('这只会删除应用内的历史记录，不会删除下载文件。'),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(confirmContext).pop(false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(confirmContext).pop(true),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await store.clear();
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
                child: const Text('清空历史'),
              ),
            TextButton(
              key: const Key('browser-close-history-dialog'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
