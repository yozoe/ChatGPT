import 'package:flutter/material.dart';

/// Dialog that selects which browser data domains should be cleared.
class BrowserClearDataDialog extends StatelessWidget {
  const BrowserClearDataDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final selected = <String>{'website', 'cache', 'history', 'downloads'};
    return StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('清除浏览数据？'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('选择要清除的范围。已保存的下载文件不会被删除。'),
              ),
              CheckboxListTile(
                key: const Key('browser-clear-website-data'),
                dense: true,
                title: const Text('Cookie 和网站存储'),
                value: selected.contains('website'),
                onChanged: (value) => setDialogState(() {
                  if (value == true) {
                    selected.add('website');
                  } else {
                    selected.remove('website');
                  }
                }),
              ),
              CheckboxListTile(
                key: const Key('browser-clear-cache'),
                dense: true,
                title: const Text('缓存'),
                value: selected.contains('cache'),
                onChanged: (value) => setDialogState(() {
                  if (value == true) {
                    selected.add('cache');
                  } else {
                    selected.remove('cache');
                  }
                }),
              ),
              CheckboxListTile(
                key: const Key('browser-clear-history-data'),
                dense: true,
                title: const Text('浏览历史和导航历史'),
                value: selected.contains('history'),
                onChanged: (value) => setDialogState(() {
                  if (value == true) {
                    selected.add('history');
                  } else {
                    selected.remove('history');
                  }
                }),
              ),
              CheckboxListTile(
                key: const Key('browser-clear-download-data'),
                dense: true,
                title: const Text('下载记录'),
                value: selected.contains('downloads'),
                onChanged: (value) => setDialogState(() {
                  if (value == true) {
                    selected.add('downloads');
                  } else {
                    selected.remove('downloads');
                  }
                }),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(selected),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}
