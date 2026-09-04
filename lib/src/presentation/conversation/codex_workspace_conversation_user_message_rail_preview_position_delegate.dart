// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;

import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

/// Positions a rail preview beside its mark while keeping it on-screen.
class ConversationUserMessageRailPreviewPositionDelegate
    extends SingleChildLayoutDelegate {
  const ConversationUserMessageRailPreviewPositionDelegate({
    required this.anchor,
    required this.preferredWidth,
    required this.maximumHeight,
    required this.gap,
    required this.viewportInset,
  });

  final Rect anchor;
  final double preferredWidth;
  final double maximumHeight;
  final double gap;
  final double viewportInset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final availableWidth = math.max(
      0.0,
      constraints.maxWidth - anchor.right - gap - viewportInset,
    );
    final width = math.min(preferredWidth, availableWidth);
    final availableHeight = math.max(
      0.0,
      constraints.maxHeight - (viewportInset * 2),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.min(maximumHeight, availableHeight),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final top = (anchor.center.dy - (childSize.height / 2)).clamp(
      viewportInset,
      math.max(viewportInset, size.height - childSize.height - viewportInset),
    );
    return Offset(anchor.right + gap, top.toDouble());
  }

  @override
  bool shouldRelayout(
    covariant ConversationUserMessageRailPreviewPositionDelegate oldDelegate,
  ) =>
      anchor != oldDelegate.anchor ||
      preferredWidth != oldDelegate.preferredWidth ||
      maximumHeight != oldDelegate.maximumHeight ||
      gap != oldDelegate.gap ||
      viewportInset != oldDelegate.viewportInset;
}
