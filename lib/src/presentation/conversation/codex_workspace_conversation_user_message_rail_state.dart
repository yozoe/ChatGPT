// Extracted state from codex_workspace_conversation_user_message_rail.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:async';

import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail_mark.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail_preview.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_message_rail_preview_position_delegate.dart';

class ConversationUserMessageRailState
    extends State<ConversationUserMessageRail> {
  static const previewDelay = Duration(milliseconds: 450);
  static const previewWidth = 322.0;
  static const previewMaximumHeight = 132.0;
  static const previewGap = 14.0;
  static const previewViewportInset = 12.0;

  int? hoveredIndex;
  String? hoveredMessageId;
  Timer? previewTimer;
  OverlayEntry? previewOverlay;
  Rect? previewAnchor;
  bool previewOverlayRebuildScheduled = false;
  final Map<String, BuildContext> previewTargetContexts = {};

  void updateHoveredIndex(int? index) {
    if (hoveredIndex == index) return;
    setState(() => hoveredIndex = index);
  }

  Rect? currentPreviewAnchor() {
    final messageId = hoveredMessageId;
    final targetContext = messageId == null
        ? null
        : previewTargetContexts[messageId];
    if (targetContext == null || !targetContext.mounted) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottomRight = renderObject.localToGlobal(
      renderObject.size.bottomRight(Offset.zero),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void showPreviewAfterDelay(int index) {
    updateHoveredIndex(index);
    final messageId = widget.messages[index].id;
    hoveredMessageId = messageId;
    previewTimer?.cancel();
    previewAnchor = currentPreviewAnchor();
    if (previewAnchor == null) return;
    if (previewOverlay != null) {
      previewOverlay!.markNeedsBuild();
      return;
    }
    previewTimer = Timer(previewDelay, () {
      if (!mounted || hoveredMessageId != messageId) return;
      final overlay = Overlay.of(context);
      previewOverlay = OverlayEntry(builder: buildPreviewOverlay);
      overlay.insert(previewOverlay!);
    });
  }

  Widget buildPreviewOverlay(BuildContext overlayContext) {
    final messageId = hoveredMessageId;
    final anchor = previewAnchor;
    final index = messageId == null
        ? -1
        : widget.messages.indexWhere((message) => message.id == messageId);
    if (index < 0 || anchor == null) {
      return const SizedBox.shrink();
    }
    final message = widget.messages[index];
    return CustomSingleChildLayout(
      delegate: ConversationUserMessageRailPreviewPositionDelegate(
        anchor: anchor,
        preferredWidth: previewWidth,
        maximumHeight: previewMaximumHeight,
        gap: previewGap,
        viewportInset: previewViewportInset,
      ),
      child: ConversationUserMessageRailPreview(
        messageId: message.id,
        text: message.detail,
      ),
    );
  }

  void hidePreview() {
    previewTimer?.cancel();
    previewTimer = null;
    previewOverlay?.remove();
    previewOverlay = null;
    previewAnchor = null;
    hoveredMessageId = null;
    updateHoveredIndex(null);
  }

  void hidePreviewAfterTargetExit(String messageId) {
    previewTimer?.cancel();
    previewTimer = null;
    scheduleMicrotask(() {
      if (mounted && hoveredMessageId == messageId) hidePreview();
    });
  }

  void schedulePreviewOverlayRebuild() {
    final overlay = previewOverlay;
    if (overlay == null || previewOverlayRebuildScheduled) return;
    previewOverlayRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previewOverlayRebuildScheduled = false;
      if (!mounted || previewOverlay != overlay || !overlay.mounted) return;
      final anchor = currentPreviewAnchor();
      if (anchor == null) {
        hidePreview();
        return;
      }
      previewAnchor = anchor;
      overlay.markNeedsBuild();
    });
  }

  @override
  void didUpdateWidget(covariant ConversationUserMessageRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final messageIds = widget.messages.map((message) => message.id).toSet();
    previewTargetContexts.removeWhere(
      (messageId, _) => !messageIds.contains(messageId),
    );
    final messageId = hoveredMessageId;
    if (messageId == null) return;
    final index = widget.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) {
      hidePreview();
    } else {
      hoveredIndex = index;
      schedulePreviewOverlayRebuild();
    }
  }

  @override
  void dispose() {
    previewTimer?.cancel();
    previewOverlay?.remove();
    previewTargetContexts.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('conversation-user-message-rail'),
      container: true,
      label: '用户消息导航',
      child: MouseRegion(
        onExit: (_) => hidePreview(),
        child: SizedBox(
          width: 28,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < widget.messages.length; index++)
                      Builder(
                        builder: (targetContext) {
                          final message = widget.messages[index];
                          previewTargetContexts[message.id] = targetContext;
                          return MouseRegion(
                            key: ValueKey(
                              'conversation-user-message-rail-hit-${message.id}',
                            ),
                            opaque: true,
                            cursor: SystemMouseCursors.click,
                            onEnter: (_) => showPreviewAfterDelay(index),
                            onExit: (_) =>
                                hidePreviewAfterTargetExit(message.id),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                await widget.onMessageSelected(message.id);
                              },
                              child: Semantics(
                                button: true,
                                child: SizedBox(
                                  width: 28,
                                  height: 9,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ConversationUserMessageRailMark(
                                      messageId: message.id,
                                      text: message.detail,
                                      distanceFromHover: hoveredIndex == null
                                          ? null
                                          : (hoveredIndex! - index).abs(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
