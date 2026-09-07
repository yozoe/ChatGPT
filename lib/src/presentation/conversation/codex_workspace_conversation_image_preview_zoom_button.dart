// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_local_image_preview_state.dart';

class ImagePreviewZoomButton extends StatelessWidget {
  const ImagePreviewZoomButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        backgroundColor: LocalImagePreviewState.controlRaised,
        disabledBackgroundColor: LocalImagePreviewState.controlRaised,
      ),
      color: LocalImagePreviewState.controlInk,
      disabledColor: LocalImagePreviewState.controlMuted.withValues(
        alpha: 0.38,
      ),
      hoverColor: Colors.white12,
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
    );
  }
}
