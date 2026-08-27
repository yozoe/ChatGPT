// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_local_image_preview_state.dart';

class ImagePreviewAction extends StatelessWidget {
  const ImagePreviewAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final FutureOr<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: LocalImagePreviewState.controlSurface,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        color: LocalImagePreviewState.controlInk,
        hoverColor: Colors.white12,
        focusColor: const Color(0x336AA9DA),
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
      ),
    );
  }
}
