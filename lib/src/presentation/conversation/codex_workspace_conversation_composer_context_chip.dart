// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class ComposerContextChip extends StatelessWidget {
  const ComposerContextChip({
    required this.icon,
    required this.label,
    required this.onRemove,
    this.thumbnailPath,
    this.onPreview,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onRemove;
  final String? thumbnailPath;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thumbnailPath case final thumbnail?)
            InkWell(
              key: const Key('composer-image-thumbnail'),
              onTap: onPreview,
              borderRadius: BorderRadius.circular(7),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Image.file(
                    File(thumbnail),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: palette.field,
                      child: Icon(icon, size: 18, color: palette.muted),
                    ),
                  ),
                ),
              ),
            )
          else
            Icon(icon, size: 15, color: palette.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 3),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}
