// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class ControllerBuilder extends ConsumerWidget {
  const ControllerBuilder({required this.builder, this.overrideController});

  final CodexController? overrideController;
  final Widget Function(BuildContext context, CodexController controller)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = overrideController;
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => builder(context, controller),
      );
    }
    return builder(context, ref.watch(codexControllerProvider)!);
  }
}
