// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ExtensionSettingsNotice extends StatelessWidget {
  const ExtensionSettingsNotice({
    super.key,
    required this.icon,
    required this.message,
    this.color,
  });

  final IconData icon;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      width: double.infinity,
      color: (color ?? palette.trace).withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color ?? palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color ?? palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}
