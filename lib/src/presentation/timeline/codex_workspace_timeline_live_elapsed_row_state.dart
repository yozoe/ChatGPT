// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_live_elapsed_row.dart';

class LiveElapsedRowState extends State<LiveElapsedRow> {
  late final Timer _timer;
  late int _elapsedSeconds;

  @override
  void initState() {
    super.initState();
    _elapsedSeconds = _initialElapsedSeconds();
    // Initialize eagerly: a `late` field initializer would not start this
    // timer until the field was first read, which previously happened only in
    // dispose and left the visible counter unchanged.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final measuredSeconds = _initialElapsedSeconds();
      if (measuredSeconds == _elapsedSeconds) return;
      // Timer callbacks can be skipped while the app is suspended or the UI
      // isolate is busy. Deriving the value from the start time catches up on
      // the next callback without over-counting if delayed callbacks bunch up.
      setState(() => _elapsedSeconds = measuredSeconds);
    });
  }

  @override
  void didUpdateWidget(covariant LiveElapsedRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _elapsedSeconds = _initialElapsedSeconds();
    }
  }

  int _initialElapsedSeconds() {
    final elapsed = DateTime.now().difference(widget.startedAt).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final label =
        '已处理 ${formatLiveElapsedDuration(Duration(seconds: _elapsedSeconds))}';
    return Semantics(
      key: const Key('live-elapsed-row'),
      label: label,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 15, color: palette.muted),
            const SizedBox(width: 9),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
