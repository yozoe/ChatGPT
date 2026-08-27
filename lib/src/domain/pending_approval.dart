import 'package:chatgpt/src/services/codex_app_server.dart';

/// App Server 可能向客户端请求确认的高风险操作类别。
/// High-impact operation categories App Server may ask the client to approve.
enum ApprovalKind { command, fileChange, permissions }

/// 尚未得到用户或自动审批策略答复的 App Server 请求。
/// An App Server request awaiting user or automatic-policy resolution.
class PendingApproval {
  const PendingApproval({
    required this.requestId,
    required this.method,
    required this.params,
    required this.kind,
  });

  final Object requestId;
  final String method;
  final JsonMap params;
  final ApprovalKind kind;

  /// Thread that requested this approval, when supplied by App Server.
  String? get threadId {
    final direct = params['threadId']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final turn = params['turn'];
    final nested = turn is Map ? turn['threadId']?.toString().trim() : null;
    return nested == null || nested.isEmpty ? null : nested;
  }

  /// 返回与审批类型对应的本地化标题。
  /// Returns the localized title for this approval kind.
  String get title => switch (kind) {
    ApprovalKind.command => '命令执行请求',
    ApprovalKind.fileChange => '文件变更请求',
    ApprovalKind.permissions => '额外权限请求',
  };

  /// 汇总服务器请求中的原因、命令及权限范围。
  /// Summarizes the reason, command, and permission scope in the request.
  String get detail {
    final reason = params['reason']?.toString();
    final command = params['command']?.toString();
    final root = params['grantRoot']?.toString();
    final network = params['networkApprovalContext'];
    return [
      if (reason != null && reason.isNotEmpty) reason,
      if (command != null && command.isNotEmpty) command,
      if (root != null && root.isNotEmpty) '授权目录：$root',
      if (network != null) '网络访问：$network',
    ].join('\n');
  }

  /// 将可识别的 App Server 审批请求转换为待处理审批。
  /// Converts a recognized App Server approval request into a pending approval.
  static PendingApproval? fromEvent(ServerEvent event) {
    final requestId = event.requestId;
    if (requestId == null) return null;
    final kind = switch (event.method) {
      'item/commandExecution/requestApproval' => ApprovalKind.command,
      'item/fileChange/requestApproval' => ApprovalKind.fileChange,
      'item/permissions/requestApproval' => ApprovalKind.permissions,
      _ => null,
    };
    if (kind == null) return null;
    return PendingApproval(
      requestId: requestId,
      method: event.method,
      params: event.params,
      kind: kind,
    );
  }
}
