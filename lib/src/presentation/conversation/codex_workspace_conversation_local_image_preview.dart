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
