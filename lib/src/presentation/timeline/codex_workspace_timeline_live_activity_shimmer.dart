// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_activity_shimmer_state.dart';

class LiveActivityShimmer extends StatefulWidget {
  const LiveActivityShimmer({
    super.key,
    required this.shimmerKey,
    required this.child,
  });

  final Key shimmerKey;
  final Widget child;

  @override
  State<LiveActivityShimmer> createState() => LiveActivityShimmerState();
}
