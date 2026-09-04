import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

/// Shared right-side workbench for review and subagent panes.
class WorkspaceSidePanelTabs extends StatelessWidget {
  const WorkspaceSidePanelTabs({
    super.key,
    required this.contents,
    required this.labels,
    required this.activeTab,
    required this.onSelect,
    required this.onCollapse,
  });

  final Map<String, Widget> contents;
  final Map<String, String> labels;
  final String activeTab;
  final ValueChanged<String> onSelect;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Column(
      children: [
        Container(
          height: 62,
          decoration: BoxDecoration(
            color: palette.module,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final collapseButton = IconButton(
                key: const Key('side-panel-collapse'),
                tooltip: '收起右侧工作区',
                onPressed: onCollapse,
                style: IconButton.styleFrom(
                  backgroundColor: palette.selected,
                  minimumSize: const Size.square(40),
                  maximumSize: const Size.square(40),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: Icon(
                  Icons.view_sidebar_outlined,
                  size: 16,
                  color: palette.trace,
                ),
              );
              if (constraints.maxWidth < 72) {
                return Center(
                  child: SizedBox(
                    width: constraints.maxWidth.clamp(0, 40),
                    height: 40,
                    child: collapseButton,
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final entry in contents.keys)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Material(
                                color: entry == activeTab
                                    ? palette.selected
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  key: ValueKey('side-panel-tab-$entry'),
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => onSelect(entry),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      labels[entry] ?? entry,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: entry == activeTab
                                            ? palette.trace
                                            : palette.muted,
                                        fontSize: 12,
                                        fontWeight: entry == activeTab
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: collapseButton,
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: contents.keys
                .toList()
                .indexOf(activeTab)
                .clamp(0, contents.length - 1),
            children: [
              for (final entry in contents.entries)
                ExcludeFocus(
                  excluding: entry.key != activeTab,
                  child: entry.value,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
