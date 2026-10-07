import 'package:flutter_svg/flutter_svg.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class SettingsAppearanceSection extends StatelessWidget {
  const SettingsAppearanceSection({
    super.key,
    required this.uiFontSize,
    required this.codeFontSize,
    required this.dockIcon,
    required this.highContrast,
    required this.onHighContrastChanged,
    required this.onSelectDockIcon,
    required this.buildSettingRow,
    required this.usePointerCursor,
    required this.reduceMotion,
    required this.diffMarkers,
    required this.fontSmoothing,
  });

  final TextEditingController uiFontSize;
  final TextEditingController codeFontSize;
  final int dockIcon;
  final bool highContrast;
  final ValueChanged<bool>? onHighContrastChanged;
  final Future<void> Function(int index) onSelectDockIcon;
  final Widget Function({
    required String title,
    required String description,
    Widget? trailing,
  })
  buildSettingRow;
  final bool usePointerCursor;
  final String reduceMotion;
  final String diffMarkers;
  final bool fontSmoothing;

  Widget _fontField(TextEditingController controller) => SizedBox(
    width: 128,
    child: TextField(
      controller: controller,
      enabled: false,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: const InputDecoration(suffixText: 'px'),
    ),
  );

  Widget _dockIconTile(
    BuildContext context, {
    required int index,
    required String label,
  }) {
    final palette = YeknomPalette.of(context);
    final selected = dockIcon == index;
    return Semantics(
      label: 'Dock 图标：$label',
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('settings-dock-icon-$index'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelectDockIcon(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? palette.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? palette.trace : palette.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: index == 0
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: SvgPicture.asset(
                      'assets/branding/codex-desk-icon-traced-light.svg',
                      fit: BoxFit.contain,
                    ),
                  )
                : Image.asset('icon.png', fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final heading = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontSize: 38,
      fontWeight: FontWeight.w500,
    );
    return ListView(
      key: const Key('settings-appearance-page'),
      padding: const EdgeInsets.fromLTRB(58, 26, 58, 58),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('偏好设置', style: heading),
              const SizedBox(height: 32),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    buildSettingRow(
                      title: '使用指针光标（待开发）',
                      description: '悬停交互元素时切换为指针光标',
                      trailing: Switch(
                        value: usePointerCursor,
                        onChanged: null,
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    buildSettingRow(
                      title: '高对比度主题',
                      description: '提高文字、边框和控件状态的对比度，保持当前明暗模式与配色。',
                      trailing: Switch(
                        key: const Key('settings-high-contrast'),
                        value: highContrast,
                        onChanged: onHighContrastChanged,
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    buildSettingRow(
                      title: 'Dock 图标',
                      description: '选择应用在 Dock 中使用的图标',
                      trailing: Wrap(
                        spacing: 12,
                        children: [
                          _dockIconTile(context, index: 0, label: '结绳'),
                          _dockIconTile(context, index: 1, label: '命令云'),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    buildSettingRow(
                      title: '减少动态效果（待开发）',
                      description: '减少动画效果或匹配系统设置',
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '系统', label: Text('系统')),
                          ButtonSegment(value: '开启', label: Text('开启')),
                          ButtonSegment(value: '关闭', label: Text('关闭')),
                        ],
                        selected: {reduceMotion},
                        onSelectionChanged: null,
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    buildSettingRow(
                      title: 'UI 字号（待开发）',
                      description: '调整 ChatGPT 界面使用的基准字号',
                      trailing: _fontField(uiFontSize),
                    ),
                    Divider(height: 1, color: palette.border),
                    buildSettingRow(
                      title: '代码字体大小（待开发）',
                      description: '调整聊天和差异视图中代码使用的基础字号',
                      trailing: _fontField(codeFontSize),
                    ),
                    Divider(height: 1, color: palette.border),
                    buildSettingRow(
                      title: '差异标记（待开发）',
                      description: '使用颜色或 +/- 标记显示更改',
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '颜色', label: Text('颜色')),
                          ButtonSegment(value: '+/-', label: Text('+/-')),
                        ],
                        selected: {diffMarkers},
                        onSelectionChanged: null,
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    buildSettingRow(
                      title: '字体平滑（待开发）',
                      description: '使用 macOS 原生字体抗锯齿',
                      trailing: Switch(value: fontSmoothing, onChanged: null),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
