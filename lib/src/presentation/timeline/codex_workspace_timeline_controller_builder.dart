// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ControllerBuilder extends ConsumerWidget {
  const ControllerBuilder({
    super.key,
    required this.builder,
    this.overrideController,
  });

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
