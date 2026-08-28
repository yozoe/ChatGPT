import 'package:flutter/material.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

/// Opens the Codex-style context-window usage popover beside model controls.
class ComposerContextUsageButton extends StatelessWidget {
  const ComposerContextUsageButton({
    super.key,
    required this.usedTokens,
    required this.maximumTokens,
  });

  final int usedTokens;
  final int maximumTokens;

  String _compactTokenCount(int value) {
    if (value >= 1000) {
      final thousands = value / 1000;
      return '${thousands.round()}k';
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final ratio = maximumTokens <= 0
        ? 0.0
        : (usedTokens / maximumTokens).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    final remaining = 100 - percent;
    final warning = ratio >= 0.85;
    return PopupMenuButton<String>(
      key: const Key('composer-context-usage-button'),
      tooltip: '查看背景信息窗口',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 218),
      color: palette.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.controlBorder),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '背景信息窗口（估算）：',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '约 $percent% 已用（剩余约 $remaining%）',
                  style: TextStyle(color: palette.trace, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  '估算已用 ${_compactTokenCount(usedTokens)} 标记，共约 ${_compactTokenCount(maximumTokens)}',
                  style: TextStyle(color: palette.trace, fontSize: 13),
                ),
                if (warning) ...[
                  const SizedBox(height: 8),
                  Text(
                    '本地估算接近上限；Codex 可能压缩较早的对话内容，或建议开启新任务。',
                    style: TextStyle(color: palette.warning, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
      onSelected: (_) {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: ratio,
            strokeWidth: 2,
            backgroundColor: palette.controlBorder,
            color: warning ? palette.warning : palette.muted,
          ),
        ),
      ),
    );
  }
}
