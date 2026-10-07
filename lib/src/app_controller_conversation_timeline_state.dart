import 'package:chatgpt/src/app_controller_pending_turn_steer.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';

/// 集中维护当前会话时间线、恢复代次和待发送方向状态。
/// Owns the current conversation timeline, restore revision, and queued direction state.
///
/// 控制器仍负责事件归属、历史读写、发送编排和滚动通知；本类型只归组
/// 时间线与方向调整共享的可变状态。
/// The controller still handles event attribution, history I/O, submission
/// orchestration, and scroll notifications; this type only groups mutable
/// timeline and direction state.
class CodexConversationTimelineState {
  final List<TimelineEntry> entries = <TimelineEntry>[];
  bool resumingThread = false;
  int conversationViewRevision = 0;
  String? activeTurnId;
  final List<PendingTurnSteer> pendingTurnSteers = <PendingTurnSteer>[];
  bool pendingTurnSteerSending = false;
  PendingTurnSteer? sendingPendingTurnSteer;
  Object? pendingTurnSteerSendToken;
  DateTime? activeTurnStartedAt;

  void clearTimeline() {
    conversationViewRevision++;
    entries.clear();
    activeTurnId = null;
    activeTurnStartedAt = null;
  }

  void clearPendingSteers() {
    pendingTurnSteers.clear();
    pendingTurnSteerSending = false;
    sendingPendingTurnSteer = null;
    pendingTurnSteerSendToken = null;
  }

  void clear() {
    clearTimeline();
    resumingThread = false;
    clearPendingSteers();
  }
}
