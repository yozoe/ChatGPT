// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';

class ExtensionSettingsRow extends StatelessWidget {
  const ExtensionSettingsRow({
    super.key,
    required this.title,
    required this.enabled,
    required this.busy,
    required this.onChanged,
    this.leading,
    this.subtitle,
    this.meta,
    this.auxiliary,
    this.compact = false,
    this.active = false,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? meta;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool>? onChanged;
  final Widget? auxiliary;
  final bool compact;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: 40, height: 40, child: leading),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
          if (meta != null) ...[
            const SizedBox(width: 12),
            Text(meta!, style: TextStyle(fontSize: 12, color: palette.muted)),
          ],
          ?auxiliary,
          const SizedBox(width: 6),
          if (active)
            const SizedBox(
              key: Key('plugin-tile-progress'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Transform.scale(
              scale: 0.82,
              child: Switch.adaptive(
                value: enabled,
                onChanged: busy ? null : onChanged,
              ),
            ),
        ],
      ),
    );
  }
}
