// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class CopyCommand extends StatelessWidget {
  const CopyCommand({super.key, required this.command});
  final String command;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 5),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(command, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(width: 28),
          IconButton(
            tooltip: '复制命令',
            onPressed: () => Clipboard.setData(ClipboardData(text: command)),
            icon: const Icon(Icons.content_copy_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}
