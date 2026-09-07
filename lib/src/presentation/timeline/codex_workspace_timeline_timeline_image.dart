// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';

class TimelineImage extends StatelessWidget {
  const TimelineImage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '打开图片预览',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('timeline-image-preview-$path'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(showLocalImagePreview(context, path)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(path),
              key: ValueKey('timeline-image-$path'),
              width: 180,
              height: 130,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
