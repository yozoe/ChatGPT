// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_local_image_preview_state.dart';

class LocalImagePreview extends StatefulWidget {
  const LocalImagePreview({
    required this.path,
    required this.onOpenExternally,
    required this.onSaveCopy,
    super.key,
  });

  final String path;
  final Future<void> Function() onOpenExternally;
  final Future<void> Function() onSaveCopy;

  @override
  State<LocalImagePreview> createState() => LocalImagePreviewState();
}
