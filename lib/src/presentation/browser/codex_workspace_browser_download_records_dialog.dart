import 'package:chatgpt/src/domain/browser_download_record.dart';
import 'package:chatgpt/src/services/browser_download_store.dart';
import 'package:flutter/material.dart';

/// Dialog for viewing and removing browser download metadata without deleting files.
class BrowserDownloadRecordsDialog extends StatelessWidget {
  const BrowserDownloadRecordsDialog({
    required this.records,
    required this.store,
    super.key,
  });

  final List<BrowserDownloadRecord> records;
  final BrowserDownloadStore store;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('下载记录'),
      content: SizedBox(
        width: 560,
        height: 360,
        child: records.isEmpty
            ? const Center(child: Text('暂无下载记录'))
            : ListView.builder(
                itemCount: records.length,
                itemBuilder: (context, index) {
                  final record = records[index];
                  return ListTile(
                    title: Text(record.fileName),
                    subtitle: Text('${record.filePath}\n${record.url}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: '删除记录（不删除文件）',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await store.remove(record.filePath);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  );
                },
              ),
      ),
      actions: [
        if (records.isNotEmpty)
          TextButton(
            key: const Key('browser-clear-download-records'),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('清空下载记录？'),
                  content: const Text('只清除记录，不删除已保存的文件。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(confirmContext).pop(false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(confirmContext).pop(true),
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
            child: const Text('清空记录'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
