// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class MutedText extends StatelessWidget {
  const MutedText(this.data, {super.key});

  final String data;

  /// 构建使用低强调颜色的辅助说明文本。
  /// Builds helper text using a low-emphasis color.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Text(data, style: TextStyle(color: palette.muted, fontSize: 12));
  }
}
