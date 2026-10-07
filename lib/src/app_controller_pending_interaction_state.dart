import 'dart:async';
import 'dart:collection';

import 'package:chatgpt/src/domain/pending_approval.dart';
import 'package:chatgpt/src/domain/pending_elicitation.dart';
import 'package:chatgpt/src/domain/pending_user_input.dart';

/// 集中维护审批、MCP elicitation 和用户输入请求的队列与生命周期状态。
/// Owns queues and lifecycle state for approvals, MCP elicitations, and user-input requests.
///
/// 控制器继续负责协议响应和界面优先级计算；本类型只归组请求、顺序、
/// 自动解决计时器和响应锁。
/// The controller still handles protocol responses and presentation priority;
/// this type only groups requests, ordering, auto-resolution timers, and locks.
class CodexPendingInteractionState {
  final LinkedHashMap<Object, PendingApproval> pendingApprovals =
      LinkedHashMap();
  final LinkedHashMap<Object, PendingElicitation> pendingElicitations =
      LinkedHashMap();
  final LinkedHashMap<Object, PendingUserInputRequest> pendingUserInputs =
      LinkedHashMap();
  final Map<String, Object> autoResolvingUserInputByThread = <String, Object>{};
  final Map<Object, Timer> userInputAutoResolutionTimers = <Object, Timer>{};
  final Map<Object, String> userInputAutoResolutionStates = <Object, String>{};
  final Map<Object, DateTime> userInputAutoResolutionDeadlines =
      <Object, DateTime>{};
  final List<({Object requestId, String kind})> pendingRequestOrder = [];
  bool userInputSurfaceForegrounded = false;
  String? presentedUserInputThreadId;

  bool approvalResponding = false;
  bool elicitationResponding = false;
  bool userInputResponding = false;

  void clearUserInputAutoResolution() {
    for (final timer in userInputAutoResolutionTimers.values) {
      timer.cancel();
    }
    userInputAutoResolutionTimers.clear();
    userInputAutoResolutionStates.clear();
    userInputAutoResolutionDeadlines.clear();
    autoResolvingUserInputByThread.clear();
  }

  /// Clears protocol requests that cannot survive a runtime disconnect while
  /// preserving presentation ownership markers for the current surface.
  void clearForRuntimeDisconnect() {
    pendingApprovals.clear();
    pendingElicitations.clear();
    pendingUserInputs.clear();
    pendingRequestOrder.clear();
    clearUserInputAutoResolution();
    approvalResponding = false;
    elicitationResponding = false;
    userInputResponding = false;
  }

  void clear() {
    clearForRuntimeDisconnect();
    userInputSurfaceForegrounded = false;
    presentedUserInputThreadId = null;
  }
}
