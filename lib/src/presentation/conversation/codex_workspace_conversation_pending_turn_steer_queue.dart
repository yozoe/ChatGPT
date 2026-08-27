// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class PendingTurnSteerQueue extends StatelessWidget {
  const PendingTurnSteerQueue({
    required this.pendingItems,
    required this.sendingAny,
    required this.isSending,
    required this.onSend,
    required this.onDiscard,
  });

  final List<PendingTurnSteer> pendingItems;
  final bool sendingAny;
  final bool Function(PendingTurnSteer) isSending;
  final Future<bool> Function(PendingTurnSteer) onSend;
  final void Function(PendingTurnSteer) onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final maxQueueHeight = math.min(
      220.0,
      math.max(54.0, MediaQuery.sizeOf(context).height * 0.28),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        key: const Key('pending-turn-steer'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: palette.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxQueueHeight),
          child: SingleChildScrollView(
            key: const Key('pending-turn-steer-scroll'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, pending) in pendingItems.indexed) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: palette.border,
                    ),
                  Padding(
                    key: ValueKey('pending-turn-steer-$index'),
                    padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 16,
                          color: palette.muted,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: SelectionArea(
                            child: Text(
                              pending.displayText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          key: index == 0
                              ? const Key('adjust-direction-button')
                              : ValueKey('adjust-direction-button-$index'),
                          onPressed: sendingAny
                              ? null
                              : () => unawaited(onSend(pending)),
                          icon: isSending(pending)
                              ? const SizedBox.square(
                                  dimension: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.reply_outlined, size: 17),
                          label: const Text('调整方向'),
                          style: TextButton.styleFrom(
                            foregroundColor: palette.muted,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        IconButton(
                          key: index == 0
                              ? const Key('discard-direction-button')
                              : ValueKey('discard-direction-button-$index'),
                          tooltip: '删除待发送方向',
                          onPressed: isSending(pending)
                              ? null
                              : () => onDiscard(pending),
                          icon: const Icon(Icons.delete_outline, size: 17),
                          color: palette.muted,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(
                            minWidth: 30,
                            minHeight: 30,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
