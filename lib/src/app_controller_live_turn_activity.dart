// Extracted class from app_controller.dart.

/// 描述当前 turn 中尚未完成的一项实时活动，可来自 App Server 或外部桥接。
/// Describes an unfinished activity in the current turn from App Server or an external bridge.
class LiveTurnActivity {
  const LiveTurnActivity({
    required this.itemId,
    required this.kind,
    required this.label,
    this.detail = '',
    this.linkedThreadId,
    this.prompt = '',
    this.status,
    this.isExternalBridge = false,
  });

  final String itemId;
  final String kind;
  final String label;
  final String detail;
  final String? linkedThreadId;
  final String prompt;
  final String? status;

  /// Whether the activity originated from the workspace bridge instead of an
  /// App Server child thread.
  final bool isExternalBridge;
}
