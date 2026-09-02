import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

class WorkspaceSidePanelLauncher extends StatelessWidget {
  const WorkspaceSidePanelLauncher({required this.onSelect, super.key});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    const items = <(String, IconData, String)>[
      ('review', Icons.difference_outlined, '审查'),
      ('terminal', Icons.terminal_outlined, '终端'),
      ('browser', Icons.language_outlined, '浏览器'),
      ('files', Icons.folder_copy_outlined, '文件'),
    ];
    return Center(
      child: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Material(
                  color: palette.module,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => onSelect(item.$1),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(item.$2, size: 16, color: palette.muted),
                          const SizedBox(width: 10),
                          Text(item.$3, style: TextStyle(color: palette.trace)),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: palette.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
